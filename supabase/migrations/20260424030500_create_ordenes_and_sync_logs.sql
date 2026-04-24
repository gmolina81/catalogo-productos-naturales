-- Migración: enums y tablas de auditoría administrativa.
--   - ordenes_proveedor (SPEC §4.1, §5.3.5): orden de compra consolidada.
--   - sync_proveedor_logs (SPEC §4.1, §5.3.3): bitácora de sincronización.
-- Ambas son admin-only (SPEC §6.4). Ningún camino público toca estas tablas.

-- ====== ordenes_proveedor ======

create type public.estado_orden_proveedor as enum (
    'borrador', 'enviada', 'recibida', 'cancelada'
);

create table public.ordenes_proveedor (
    id uuid primary key default gen_random_uuid(),
    numero bigserial not null unique,
    id_proveedor uuid not null references public.proveedores (id) on delete restrict,
    estado public.estado_orden_proveedor not null default 'borrador',
    generada_por uuid not null references auth.users (id) on delete restrict,
    fecha_creacion timestamptz not null default now(),
    ids_pedidos_incluidos uuid[] not null default '{}',
    detalle jsonb not null default '[]'::jsonb,
    total numeric(14, 2) not null default 0 check (total >= 0)
);

comment on table public.ordenes_proveedor is
    'Orden de compra consolidada al proveedor. Snapshot inmutable de qué se pidió. SPEC §4.1, §5.3.5.';
comment on column public.ordenes_proveedor.numero is
    'Número visible, bigserial autoincremental.';
comment on column public.ordenes_proveedor.ids_pedidos_incluidos is
    'Array de IDs de pedidos que cubre esta orden. Sin FK (es histórico; un pedido borrado no invalida la orden).';
comment on column public.ordenes_proveedor.detalle is
    'Snapshot jsonb: [{codigo_externo, nombre, bultos_a_pedir, precio_bulto, total_linea}].';

create index ordenes_proveedor_id_proveedor_idx
    on public.ordenes_proveedor (id_proveedor);
create index ordenes_proveedor_estado_idx
    on public.ordenes_proveedor (estado);
create index ordenes_proveedor_fecha_creacion_idx
    on public.ordenes_proveedor (fecha_creacion desc);

alter table public.ordenes_proveedor enable row level security;

create policy "admin lee ordenes_proveedor"
    on public.ordenes_proveedor for select to authenticated using (true);

create policy "admin inserta ordenes_proveedor"
    on public.ordenes_proveedor for insert to authenticated with check (true);

create policy "admin actualiza ordenes_proveedor"
    on public.ordenes_proveedor for update to authenticated
    using (true) with check (true);

create policy "admin elimina ordenes_proveedor"
    on public.ordenes_proveedor for delete to authenticated using (true);

-- ====== sync_proveedor_logs ======

create type public.origen_sync as enum ('manual', 'automatico');
create type public.estado_sync as enum ('pendiente', 'aplicado', 'descartado');

create table public.sync_proveedor_logs (
    id uuid primary key default gen_random_uuid(),
    id_proveedor uuid not null references public.proveedores (id) on delete restrict,
    ejecutado_en timestamptz not null default now(),
    ejecutado_por uuid references auth.users (id) on delete set null,
    origen public.origen_sync not null,
    cambios_detectados jsonb not null default '[]'::jsonb,
    estado public.estado_sync not null default 'pendiente',
    aplicado_en timestamptz,
    resumen jsonb not null default '{}'::jsonb
);

comment on table public.sync_proveedor_logs is
    'Bitácora de cada ejecución del sync con el proveedor. Registra diff, quién lo corrió y si se aplicó. SPEC §5.3.3.';
comment on column public.sync_proveedor_logs.ejecutado_por is
    'Admin que disparó la sincronización. NULL si corrió un cron automático (v1.1).';
comment on column public.sync_proveedor_logs.cambios_detectados is
    'Array jsonb: [{tipo, codigo_externo, antes, despues}] generado por el parser (§5.4.1).';
comment on column public.sync_proveedor_logs.resumen is
    'Conteos agregados jsonb: {nuevos, precios, bajas, otros}.';

create index sync_proveedor_logs_id_proveedor_idx
    on public.sync_proveedor_logs (id_proveedor);
create index sync_proveedor_logs_estado_idx
    on public.sync_proveedor_logs (estado);
create index sync_proveedor_logs_ejecutado_en_idx
    on public.sync_proveedor_logs (ejecutado_en desc);

alter table public.sync_proveedor_logs enable row level security;

create policy "admin lee sync_proveedor_logs"
    on public.sync_proveedor_logs for select to authenticated using (true);

create policy "admin inserta sync_proveedor_logs"
    on public.sync_proveedor_logs for insert to authenticated with check (true);

create policy "admin actualiza sync_proveedor_logs"
    on public.sync_proveedor_logs for update to authenticated
    using (true) with check (true);

-- Nota: no hay policy de DELETE. Los logs son append+update (estado,
-- aplicado_en) pero no se borran desde la app. Si hiciera falta limpieza,
-- se hace desde el dashboard (service_role bypass).
