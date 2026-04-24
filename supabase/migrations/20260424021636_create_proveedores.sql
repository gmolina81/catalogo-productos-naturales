-- Migración: crear tabla `proveedores` (SPEC §4.1).
-- Política RLS: solo admin autenticado puede leer/escribir (SPEC §6.4).
-- En v1 la tabla contiene una única fila (el proveedor New Garden), pero el modelo
-- queda listo para multiproveedor sin requerir migración futura.

create table public.proveedores (
    id uuid primary key default gen_random_uuid(),
    nombre text not null,
    sheet_id text not null,
    sheet_range text,
    contacto_whatsapp text not null,
    contacto_email text,
    activo boolean not null default true,
    created_at timestamptz not null default now()
);

comment on table public.proveedores is
    'Proveedores mayoristas. En v1 una única fila; modelo listo para multiproveedor (SPEC §1.5).';
comment on column public.proveedores.sheet_id is
    'ID de la Google Sheet del proveedor (la parte entre /d/ y /edit del URL).';
comment on column public.proveedores.sheet_range is
    'Rango o tab dentro de la Sheet, si aplica. Null si se usa la default.';

create index proveedores_activo_idx on public.proveedores (activo);

alter table public.proveedores enable row level security;

-- Políticas: en v1, `authenticated` = admin (única cuenta). SPEC §6.4.
-- anon no tiene ninguna policy y por lo tanto no puede hacer nada (RLS denied).

create policy "admin puede leer proveedores"
    on public.proveedores
    for select
    to authenticated
    using (true);

create policy "admin puede insertar proveedores"
    on public.proveedores
    for insert
    to authenticated
    with check (true);

create policy "admin puede actualizar proveedores"
    on public.proveedores
    for update
    to authenticated
    using (true)
    with check (true);

create policy "admin puede eliminar proveedores"
    on public.proveedores
    for delete
    to authenticated
    using (true);
