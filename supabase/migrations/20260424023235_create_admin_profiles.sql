-- Migración: enum `admin_rol` y tabla `admin_profiles` (SPEC §4.1).
-- Política RLS: cada admin solo lee/modifica su propia fila (SPEC §6.4).
-- En v1 existe una única cuenta (rol `admin`); `vendedor` queda listo para v1.1.

create type public.admin_rol as enum ('admin', 'vendedor');

create table public.admin_profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    nombre text not null,
    rol public.admin_rol not null default 'admin',
    activo boolean not null default true,
    created_at timestamptz not null default now()
);

comment on table public.admin_profiles is
    'Perfil visible del usuario de Supabase Auth. 1:1 con auth.users. SPEC §4.1.';

create index admin_profiles_rol_idx on public.admin_profiles (rol);

alter table public.admin_profiles enable row level security;

-- Cada usuario autenticado ve/escribe solo su propia fila.
-- `(select auth.uid())` en vez de `auth.uid()` para que el optimizador
-- use initPlan (CLAUDE.md §8.2).

create policy "admin lee su propio perfil"
    on public.admin_profiles
    for select
    to authenticated
    using (id = (select auth.uid()));

create policy "admin inserta su propio perfil"
    on public.admin_profiles
    for insert
    to authenticated
    with check (id = (select auth.uid()));

create policy "admin actualiza su propio perfil"
    on public.admin_profiles
    for update
    to authenticated
    using (id = (select auth.uid()))
    with check (id = (select auth.uid()));

-- No hay policy de DELETE: la baja de cuenta se hace desde el dashboard de Supabase,
-- no desde la app. auth.users on delete cascade se encarga de limpiar esta fila.
