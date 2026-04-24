-- Migración: tabla `clientes` y RPC `upsert_cliente` (SPEC §4.1, §5.2, §6.4).
--
-- Los clientes no tienen cuenta de Auth; se identifican por email. El checkout
-- público necesita crear o actualizar un cliente por email. Para no darle a anon
-- permisos directos de INSERT/UPDATE sobre la tabla (que derivaría en la posibilidad
-- de modificar datos ajenos sabiendo el email), exponemos el upsert como una RPC
-- `SECURITY DEFINER` que corre con privilegios elevados y valida inputs.
--
-- Así los policies directos de la tabla quedan admin-only:
--   SELECT / UPDATE / DELETE → solo authenticated (admin).
--   INSERT / UPDATE directos → sin policy → bloqueados.

create table public.clientes (
    id uuid primary key default gen_random_uuid(),
    nombre text not null,
    telefono text not null,
    email text not null unique,
    direccion text,
    notas text,
    created_at timestamptz not null default now()
);

comment on table public.clientes is
    'Clientes del negocio. No tienen cuenta de Auth; se identifican por email. SPEC §4.1.';
comment on column public.clientes.email is
    'Clave natural de identificación. El checkout hace upsert contra esta columna vía RPC.';

-- Índice implícito en UNIQUE(email) ya existe; el de created_at ayuda al listado admin por fecha.
create index clientes_created_at_idx on public.clientes (created_at desc);

alter table public.clientes enable row level security;

-- Policies admin-only. anon no tiene policy para INSERT ni UPDATE → usa solo la RPC.

create policy "admin lee clientes"
    on public.clientes
    for select
    to authenticated
    using (true);

create policy "admin actualiza clientes"
    on public.clientes
    for update
    to authenticated
    using (true)
    with check (true);

create policy "admin elimina clientes"
    on public.clientes
    for delete
    to authenticated
    using (true);

-- ====== RPC público para el checkout (SECURITY DEFINER) ======
--
-- Hace INSERT si el email es nuevo, UPDATE si ya existe. Preserva direccion y notas
-- si el caller pasa NULL (COALESCE). Valida formato de email, longitud mínima de
-- nombre y teléfono. `set search_path = ''` previene search_path injection;
-- dentro del cuerpo se usan nombres calificados.

create or replace function public.upsert_cliente(
    p_email text,
    p_nombre text,
    p_telefono text,
    p_direccion text default null,
    p_notas text default null
) returns uuid
    language plpgsql
    security definer
    set search_path = ''
as $$
declare
    v_id uuid;
    v_email text;
begin
    v_email := lower(trim(coalesce(p_email, '')));

    if v_email = '' or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
        raise exception 'email inválido' using errcode = '22023';
    end if;
    if coalesce(length(trim(p_nombre)), 0) < 2 then
        raise exception 'nombre inválido' using errcode = '22023';
    end if;
    if coalesce(length(trim(p_telefono)), 0) < 5 then
        raise exception 'teléfono inválido' using errcode = '22023';
    end if;

    insert into public.clientes (email, nombre, telefono, direccion, notas)
    values (v_email, trim(p_nombre), trim(p_telefono), p_direccion, p_notas)
    on conflict (email) do update
        set nombre = excluded.nombre,
            telefono = excluded.telefono,
            direccion = coalesce(excluded.direccion, public.clientes.direccion),
            notas = coalesce(excluded.notas, public.clientes.notas)
    returning id into v_id;

    return v_id;
end;
$$;

comment on function public.upsert_cliente(text, text, text, text, text) is
    'Checkout público (SPEC §5.2). Crea o actualiza cliente por email. SECURITY DEFINER: corre con privilegios elevados y bypassa RLS. Valida email, nombre y teléfono. Preserva direccion/notas si se pasan NULL.';

-- Revocar el grant default de PUBLIC y otorgar explícitamente solo a anon + authenticated.
revoke execute on function public.upsert_cliente(text, text, text, text, text) from public;
grant execute on function public.upsert_cliente(text, text, text, text, text) to anon, authenticated;
