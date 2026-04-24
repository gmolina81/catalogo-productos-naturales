-- Migración: enum `precio_modo`, tabla `productos_negocio`, tabla `mapeo_pack_bulto`.
-- (SPEC §4.1, decisiones cerradas en §9.1: markup default 20%, soft delete).
--
-- `productos_negocio` es la oferta pública del negocio (lo que ve el cliente).
-- Se carga en Fase 1.4 desde `files/MM_productos_naturales.xlsx` con
-- `id_producto_proveedor = NULL`, y el admin lo asocia al proveedor en Fase 2.
--
-- `mapeo_pack_bulto` es 1:1 con productos_negocio: cuántos packs salen de un bulto.

create type public.precio_modo as enum ('manual', 'markup_sobre_costo');

create table public.productos_negocio (
    id uuid primary key default gen_random_uuid(),
    id_producto_proveedor uuid
        references public.productos_proveedor (id) on delete set null,
    nombre_publico text not null,
    categoria text not null,
    descripcion text,
    presentacion text not null,
    precio_venta numeric(12, 2) not null,
    precio_modo public.precio_modo not null default 'markup_sobre_costo',
    markup_pct numeric(6, 2) default 20,
    imagen text,
    activo boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint productos_negocio_markup_consistente
        check (
            (precio_modo = 'markup_sobre_costo' and markup_pct is not null)
            or precio_modo = 'manual'
        )
);

comment on table public.productos_negocio is
    'Oferta curada que ve el cliente. Puede o no estar vinculada a productos_proveedor. SPEC §4.1.';
comment on column public.productos_negocio.id_producto_proveedor is
    'Nullable en v1. Los packs cargados desde el Excel del negocio no tienen vínculo al proveedor hasta que el admin los asocie en Fase 2.';
comment on column public.productos_negocio.activo is
    'Visibilidad pública. Soft delete (§9.1): al dar de baja se apaga, no se borra.';

create table public.mapeo_pack_bulto (
    id uuid primary key default gen_random_uuid(),
    id_producto_negocio uuid not null unique
        references public.productos_negocio (id) on delete cascade,
    packs_por_bulto numeric(10, 2) not null,
    merma_pct numeric(6, 2) not null default 0,
    notas text
);

comment on table public.mapeo_pack_bulto is
    'Relación 1:1 con productos_negocio. Cuántos packs salen de un bulto y qué merma esperar. SPEC §4.1, §5.4.3.';

-- Índices para queries frecuentes y RLS-friendly filtering.
create index productos_negocio_activo_idx on public.productos_negocio (activo);
create index productos_negocio_categoria_idx on public.productos_negocio (categoria);
create index productos_negocio_id_producto_proveedor_idx
    on public.productos_negocio (id_producto_proveedor);

-- ====== Trigger para mantener updated_at ======

create or replace function public.set_updated_at()
    returns trigger
    language plpgsql
    as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

create trigger productos_negocio_set_updated_at
    before update on public.productos_negocio
    for each row execute function public.set_updated_at();

-- ====== RLS: productos_negocio (mixto anon + admin) ======

alter table public.productos_negocio enable row level security;

-- El catálogo público es accesible para anon SOLO cuando activo = true.
create policy "público lee productos activos"
    on public.productos_negocio
    for select
    to anon
    using (activo = true);

-- El admin ve todo, incluyendo inactivos.
create policy "admin lee todo"
    on public.productos_negocio
    for select
    to authenticated
    using (true);

create policy "admin inserta productos_negocio"
    on public.productos_negocio
    for insert
    to authenticated
    with check (true);

create policy "admin actualiza productos_negocio"
    on public.productos_negocio
    for update
    to authenticated
    using (true)
    with check (true);

create policy "admin elimina productos_negocio"
    on public.productos_negocio
    for delete
    to authenticated
    using (true);

-- ====== RLS: mapeo_pack_bulto (solo admin) ======

alter table public.mapeo_pack_bulto enable row level security;

create policy "admin lee mapeo_pack_bulto"
    on public.mapeo_pack_bulto
    for select
    to authenticated
    using (true);

create policy "admin inserta mapeo_pack_bulto"
    on public.mapeo_pack_bulto
    for insert
    to authenticated
    with check (true);

create policy "admin actualiza mapeo_pack_bulto"
    on public.mapeo_pack_bulto
    for update
    to authenticated
    using (true)
    with check (true);

create policy "admin elimina mapeo_pack_bulto"
    on public.mapeo_pack_bulto
    for delete
    to authenticated
    using (true);
