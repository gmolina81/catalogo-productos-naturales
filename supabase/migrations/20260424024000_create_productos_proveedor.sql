-- Migración: enum `estado_producto_proveedor` y tabla `productos_proveedor`
-- (SPEC §4.1, reescrita en v1.4).
--
-- Cada fila representa una combinación (producto base, presentación) del
-- proveedor. La Sheet del proveedor no tiene clave natural estable, así que
-- `codigo_externo` se genera sintéticamente como slug(nombre_base)|slug(presentacion)
-- y la unicidad real es (id_proveedor, codigo_externo).
--
-- Política RLS: SPEC §6.4 — solo admin autenticado (v1 = `authenticated`).

create type public.estado_producto_proveedor as enum (
    'activo',
    'baja',
    'sin_precio'
);

create table public.productos_proveedor (
    id uuid primary key default gen_random_uuid(),
    id_proveedor uuid not null references public.proveedores (id) on delete restrict,
    codigo_externo text not null,
    nombre_base text not null,
    nombre_original text not null,
    presentacion text not null,
    categoria text not null,
    descripcion text,
    precio_bulto numeric(12, 2),
    unidad_compra text not null,
    imagen text,
    estado public.estado_producto_proveedor not null default 'activo',
    ultima_sync timestamptz not null default now(),
    reemplaza_a uuid references public.productos_proveedor (id) on delete set null,
    constraint productos_proveedor_codigo_externo_unique
        unique (id_proveedor, codigo_externo)
);

comment on table public.productos_proveedor is
    'Snapshot de la Sheet del proveedor. Cada fila es una combinación (producto, presentación). SPEC §4.1.';
comment on column public.productos_proveedor.codigo_externo is
    'Clave natural sintética: slug(nombre_base)|slug(presentacion). Ver §5.3.3.1.';
comment on column public.productos_proveedor.nombre_original is
    'Nombre exacto como aparece en la Sheet, sin normalizar. Para auditoría y debug de matching.';
comment on column public.productos_proveedor.estado is
    '`activo` vigente, `baja` retirado por el proveedor, `sin_precio` en la Sheet pero sin precio publicado.';
comment on column public.productos_proveedor.reemplaza_a is
    'Si el admin fusionó este registro con uno dado de baja (cambio tipográfico del proveedor), apunta al anterior. §5.3.3.';

-- Índices sobre columnas usadas en queries frecuentes y RLS (CLAUDE.md §8.1).
create index productos_proveedor_id_proveedor_idx
    on public.productos_proveedor (id_proveedor);
create index productos_proveedor_estado_idx
    on public.productos_proveedor (estado);
create index productos_proveedor_categoria_idx
    on public.productos_proveedor (categoria);

alter table public.productos_proveedor enable row level security;

-- En v1 authenticated = admin. Todo solo admin.

create policy "admin puede leer productos_proveedor"
    on public.productos_proveedor
    for select
    to authenticated
    using (true);

create policy "admin puede insertar productos_proveedor"
    on public.productos_proveedor
    for insert
    to authenticated
    with check (true);

create policy "admin puede actualizar productos_proveedor"
    on public.productos_proveedor
    for update
    to authenticated
    using (true)
    with check (true);

create policy "admin puede eliminar productos_proveedor"
    on public.productos_proveedor
    for delete
    to authenticated
    using (true);
