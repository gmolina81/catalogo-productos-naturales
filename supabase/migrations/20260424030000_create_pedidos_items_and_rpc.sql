-- Migración: enums estado_pedido/canal_pedido, tablas pedidos + pedido_items,
-- y RPC `crear_pedido` para el checkout atómico (SPEC §4.1, §5.2, §6.4).
--
-- Estrategia (consistente con clientes/upsert_cliente):
-- - anon NO recibe grants directos sobre pedidos/pedido_items. Todo el checkout
--   pasa por `crear_pedido`, que es SECURITY DEFINER y corre la transacción completa.
-- - admin tiene policies SELECT/UPDATE/DELETE sobre ambas tablas.
-- - pedido_items.subtotal es una columna GENERATED (cantidad * precio_unitario).

create type public.estado_pedido as enum (
    'pendiente', 'confirmado', 'preparando', 'listo', 'entregado', 'cancelado'
);

create type public.canal_pedido as enum ('web', 'whatsapp', 'manual');

-- ====== pedidos ======

create table public.pedidos (
    id uuid primary key default gen_random_uuid(),
    numero bigserial not null unique,
    id_cliente uuid not null references public.clientes (id) on delete restrict,
    estado public.estado_pedido not null default 'pendiente',
    canal public.canal_pedido not null default 'web',
    total numeric(12, 2) not null default 0 check (total >= 0),
    notas_cliente text,
    notas_admin text,
    fecha_pedido timestamptz not null default now(),
    fecha_entrega_estimada date
);

comment on table public.pedidos is
    'Pedidos del cliente. anon los crea vía RPC crear_pedido. SPEC §4.1, §5.2.';
comment on column public.pedidos.numero is
    'Número visible al cliente, serial autoincremental.';

create index pedidos_id_cliente_idx on public.pedidos (id_cliente);
create index pedidos_estado_idx on public.pedidos (estado);
create index pedidos_fecha_pedido_idx on public.pedidos (fecha_pedido desc);

alter table public.pedidos enable row level security;

create policy "admin lee pedidos"
    on public.pedidos for select to authenticated using (true);

create policy "admin actualiza pedidos"
    on public.pedidos for update to authenticated
    using (true) with check (true);

create policy "admin elimina pedidos"
    on public.pedidos for delete to authenticated using (true);

-- ====== pedido_items ======

create table public.pedido_items (
    id uuid primary key default gen_random_uuid(),
    id_pedido uuid not null references public.pedidos (id) on delete cascade,
    id_producto_negocio uuid not null references public.productos_negocio (id) on delete restrict,
    cantidad integer not null check (cantidad > 0),
    precio_unitario numeric(12, 2) not null check (precio_unitario >= 0),
    subtotal numeric(14, 2) generated always as (cantidad * precio_unitario) stored
);

comment on table public.pedido_items is
    'Líneas de pedido. Se insertan junto con el pedido vía crear_pedido. SPEC §4.1.';
comment on column public.pedido_items.precio_unitario is
    'Snapshot del precio al momento del pedido (no se actualiza después). SPEC §5.2.';
comment on column public.pedido_items.subtotal is
    'Columna GENERATED: siempre igual a cantidad * precio_unitario (DB garantiza consistencia).';

create index pedido_items_id_pedido_idx on public.pedido_items (id_pedido);
create index pedido_items_id_producto_negocio_idx
    on public.pedido_items (id_producto_negocio);

alter table public.pedido_items enable row level security;

create policy "admin lee pedido_items"
    on public.pedido_items for select to authenticated using (true);

create policy "admin actualiza pedido_items"
    on public.pedido_items for update to authenticated
    using (true) with check (true);

create policy "admin elimina pedido_items"
    on public.pedido_items for delete to authenticated using (true);

-- ====== RPC crear_pedido ======

create or replace function public.crear_pedido(
    p_email text,
    p_nombre text,
    p_telefono text,
    p_items jsonb,
    p_direccion text default null,
    p_notas_cliente text default null,
    p_fecha_entrega_estimada date default null
) returns jsonb
    language plpgsql
    security definer
    set search_path = ''
as $$
declare
    v_id_cliente uuid;
    v_id_pedido uuid;
    v_numero bigint;
    v_total numeric(14, 2) := 0;
    v_item jsonb;
    v_id_pn uuid;
    v_cantidad integer;
    v_precio numeric(12, 2);
begin
    -- 0) Validar que items sea array no vacío
    if p_items is null or jsonb_typeof(p_items) <> 'array'
       or jsonb_array_length(p_items) = 0 then
        raise exception 'items requerido: array jsonb con al menos 1 elemento'
            using errcode = '22023';
    end if;

    -- 1) Upsert del cliente (valida email/nombre/telefono internamente)
    v_id_cliente := public.upsert_cliente(
        p_email, p_nombre, p_telefono, p_direccion, p_notas_cliente
    );

    -- 2) Crear el pedido en estado pendiente, total=0 temporal
    insert into public.pedidos (id_cliente, canal, notas_cliente, fecha_entrega_estimada)
    values (v_id_cliente, 'web', p_notas_cliente, p_fecha_entrega_estimada)
    returning id, numero into v_id_pedido, v_numero;

    -- 3) Iterar items y crear pedido_items con snapshot de precio
    for v_item in select * from jsonb_array_elements(p_items)
    loop
        v_id_pn := (v_item->>'id_producto_negocio')::uuid;
        v_cantidad := (v_item->>'cantidad')::integer;

        if v_cantidad is null or v_cantidad <= 0 then
            raise exception 'cantidad inválida (debe ser entero > 0)'
                using errcode = '22023';
        end if;

        -- Tomar precio_venta del pack solo si está activo. Si no existe o no está activo,
        -- lanzamos 22023 para dar un error uniforme al frontend (no 23503/23514).
        select precio_venta into v_precio
        from public.productos_negocio
        where id = v_id_pn and activo = true;

        if v_precio is null then
            raise exception 'producto_negocio inexistente o inactivo: %', v_id_pn
                using errcode = '22023';
        end if;

        insert into public.pedido_items
            (id_pedido, id_producto_negocio, cantidad, precio_unitario)
        values (v_id_pedido, v_id_pn, v_cantidad, v_precio);

        v_total := v_total + (v_cantidad * v_precio);
    end loop;

    -- 4) Actualizar total del pedido con la suma
    update public.pedidos set total = v_total where id = v_id_pedido;

    return jsonb_build_object(
        'id', v_id_pedido,
        'numero', v_numero,
        'total', v_total
    );
end;
$$;

comment on function public.crear_pedido(text, text, text, jsonb, text, text, date) is
    'Checkout atómico: upsert cliente, insert pedido, insert pedido_items con snapshot de precios, calcular total. SECURITY DEFINER. SPEC §5.2.';

revoke execute on function public.crear_pedido(text, text, text, jsonb, text, text, date) from public;
grant execute on function public.crear_pedido(text, text, text, jsonb, text, text, date) to anon, authenticated;
