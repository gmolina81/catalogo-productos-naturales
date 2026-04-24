-- Migración: tabla `admin_audit_log` (trazabilidad append-only de acciones admin).
-- Spec: SPEC §4.1, §6.1 (principio de auditoría), §6.4 (solo SELECT para admin;
-- INSERT mediante función SECURITY DEFINER; nadie puede UPDATE ni DELETE).
--
-- Diseño append-only desde el cliente:
--   - Única policy en la tabla: SELECT para authenticated.
--   - Sin policies de INSERT/UPDATE/DELETE → ningún rol cliente puede modificar
--     ni borrar registros. Si la cuenta admin se compromete, el atacante no
--     puede borrar el rastro.
--   - Para escribir, admin llama a public.log_admin_action. La función es
--     SECURITY DEFINER, corre como postgres, bypassa RLS y graba la fila.

create type public.audit_accion as enum (
    'login',
    'logout',
    'crear_pack',
    'editar_pack',
    'eliminar_pack',
    'aplicar_sync',
    'cambiar_estado_pedido',
    'generar_orden_compra'
);

create table public.admin_audit_log (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users (id) on delete set null,
    accion public.audit_accion not null,
    entidad text,
    entidad_id uuid,
    detalle jsonb not null default '{}'::jsonb,
    ip_origen inet,
    user_agent text,
    creado_en timestamptz not null default now()
);

comment on table public.admin_audit_log is
    'Trazabilidad inmutable de acciones admin. Append-only desde el cliente. SPEC §4.1, §6.1.';
comment on column public.admin_audit_log.user_id is
    'Admin que hizo la acción. Nullable como reserva para futuros eventos sin sesión autenticada. ON DELETE SET NULL preserva el log aunque se elimine la cuenta.';
comment on column public.admin_audit_log.detalle is
    'Snapshot jsonb con antes/después u otros datos de contexto. Por ejemplo, al cambiar_estado_pedido: {"de":"pendiente","a":"confirmado","id_pedido":"..."}';

create index admin_audit_log_user_id_idx on public.admin_audit_log (user_id);
create index admin_audit_log_accion_idx on public.admin_audit_log (accion);
create index admin_audit_log_creado_en_idx on public.admin_audit_log (creado_en desc);
create index admin_audit_log_entidad_idx on public.admin_audit_log (entidad, entidad_id);

alter table public.admin_audit_log enable row level security;

-- ÚNICA policy: admin puede leer. Sin INSERT/UPDATE/DELETE policies:
-- el cliente no puede escribir ni modificar estos registros.
create policy "admin lee admin_audit_log"
    on public.admin_audit_log
    for select
    to authenticated
    using (true);

-- ====== RPC log_admin_action (SECURITY DEFINER) ======
--
-- Único punto de escritura a admin_audit_log. Setea user_id desde auth.uid()
-- automáticamente: el caller no puede falsificar quién hizo la acción.

create or replace function public.log_admin_action(
    p_accion public.audit_accion,
    p_entidad text default null,
    p_entidad_id uuid default null,
    p_detalle jsonb default '{}'::jsonb,
    p_ip_origen inet default null,
    p_user_agent text default null
) returns uuid
    language plpgsql
    security definer
    set search_path = ''
as $$
declare
    v_user_id uuid;
    v_log_id uuid;
begin
    v_user_id := (select auth.uid());

    if v_user_id is null then
        raise exception 'log_admin_action requiere sesión autenticada'
            using errcode = '42501';
    end if;

    insert into public.admin_audit_log
        (user_id, accion, entidad, entidad_id, detalle, ip_origen, user_agent)
    values
        (v_user_id, p_accion, p_entidad, p_entidad_id,
         coalesce(p_detalle, '{}'::jsonb), p_ip_origen, p_user_agent)
    returning id into v_log_id;

    return v_log_id;
end;
$$;

comment on function public.log_admin_action(
    public.audit_accion, text, uuid, jsonb, inet, text
) is
    'Único punto de escritura a admin_audit_log. SECURITY DEFINER. Setea user_id desde auth.uid(), rechaza llamadas sin sesión. SPEC §6.4.';

-- Solo authenticated puede llamarla. anon no tiene nada que auditar.
-- Supabase grantea por default EXECUTE a anon en funciones de public, así que
-- además de revocar a PUBLIC hay que revocar explícitamente a anon.
revoke execute on function public.log_admin_action(
    public.audit_accion, text, uuid, jsonb, inet, text
) from public, anon;
grant execute on function public.log_admin_action(
    public.audit_accion, text, uuid, jsonb, inet, text
) to authenticated;
