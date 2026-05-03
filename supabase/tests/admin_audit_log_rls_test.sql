-- Tests para la tabla `admin_audit_log` (trazabilidad inmutable de acciones admin).
-- Spec: SPEC §4.1 (estructura), §6.4 (admin SELECT; sin UPDATE/DELETE para nadie;
-- INSERT solo vía función SECURITY DEFINER), §6.1 (principio de auditoría).
-- Estándar: CLAUDE.md §6.3.
--
-- Diseño append-only:
-- - Table policies: SOLO "authenticated SELECT". Sin UPDATE, sin DELETE,
--   sin INSERT → nadie puede modificar ni borrar registros desde el cliente.
-- - Inserción vía public.log_admin_action(accion, entidad, entidad_id,
--   detalle, ip_origen, user_agent) SECURITY DEFINER.
-- - Si la cuenta admin se compromete, el atacante no puede borrar el rastro.

BEGIN;

SELECT plan(20);

-- ====== Estructura ======

SELECT has_type('public', 'audit_accion', 'enum audit_accion existe');

SELECT has_table('public', 'admin_audit_log', 'tabla admin_audit_log existe');

SELECT columns_are(
    'public', 'admin_audit_log',
    ARRAY['id', 'user_id', 'accion', 'entidad', 'entidad_id',
          'detalle', 'ip_origen', 'user_agent', 'creado_en'],
    'admin_audit_log tiene las 9 columnas de SPEC §4.1'
);

SELECT col_is_pk('public', 'admin_audit_log', 'id', 'id es PK');

SELECT fk_ok(
    'public', 'admin_audit_log', 'user_id',
    'auth', 'users', 'id',
    'user_id es FK a auth.users.id'
);

SELECT col_is_null(
    'public', 'admin_audit_log', 'user_id',
    'user_id es nullable (reserva para futuro: eventos sin usuario autenticado)'
);

SELECT col_not_null('public', 'admin_audit_log', 'accion', 'accion NOT NULL');
SELECT col_not_null('public', 'admin_audit_log', 'creado_en', 'creado_en NOT NULL');

SELECT ok(
    (SELECT relrowsecurity FROM pg_class
     WHERE oid = 'public.admin_audit_log'::regclass),
    'RLS habilitado en admin_audit_log'
);

-- Solo debe existir policy de SELECT. No UPDATE, no DELETE, no INSERT.
SELECT is(
    (SELECT count(*)::int FROM pg_policies
     WHERE schemaname = 'public' AND tablename = 'admin_audit_log'),
    1,
    'admin_audit_log tiene exactamente 1 policy (SELECT) — append-only desde el cliente'
);

SELECT has_function(
    'public', 'log_admin_action',
    ARRAY['public.audit_accion', 'text', 'uuid', 'jsonb', 'inet', 'text'],
    'función log_admin_action(accion, entidad, entidad_id, detalle, ip_origen, user_agent) existe'
);

-- ====== Fixture: un usuario admin fake ======
-- Limpiar la tabla: tests de integración previos pueden haber dejado filas
-- (admin_audit_log no tiene policy DELETE, por eso usamos TRUNCATE como
-- postgres dentro de la transacción del test; ROLLBACK al final restaura).
TRUNCATE public.admin_audit_log;

INSERT INTO auth.users (id, is_sso_user, is_anonymous)
VALUES ('99999999-9999-9999-9999-999999999999', false, false);

-- ====== Comportamiento: anon ======

SET LOCAL ROLE anon;

SELECT throws_ok(
    $$ INSERT INTO public.admin_audit_log (accion) VALUES ('login') $$,
    '42501',
    NULL,
    'anon no puede INSERT directo en admin_audit_log'
);

-- ====== Comportamiento: authenticated (admin) ======

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" TO
    '{"sub":"99999999-9999-9999-9999-999999999999","role":"authenticated"}';

-- authenticated tampoco puede INSERT directo (no hay policy).
SELECT throws_ok(
    $$ INSERT INTO public.admin_audit_log (user_id, accion)
       VALUES ('99999999-9999-9999-9999-999999999999', 'login') $$,
    '42501',
    NULL,
    'authenticated tampoco puede INSERT directo (solo vía log_admin_action)'
);

-- authenticated SÍ puede llamar la RPC: registra la fila con user_id = auth.uid().
SELECT lives_ok(
    $$ SELECT public.log_admin_action(
        'login'::public.audit_accion,
        NULL, NULL,
        '{"detalle":"login exitoso"}'::jsonb,
        NULL, NULL
    ) $$,
    'authenticated puede llamar log_admin_action'
);

-- La fila insertada tiene user_id = el auth.uid() del caller, no parámetro.
SELECT is(
    (SELECT user_id FROM public.admin_audit_log
     WHERE accion = 'login' LIMIT 1),
    '99999999-9999-9999-9999-999999999999'::uuid,
    'log_admin_action setea user_id desde auth.uid() automáticamente'
);

-- Intento de UPDATE desde admin: no hay policy → 0 filas afectadas, silencioso.
SELECT is_empty(
    $$ UPDATE public.admin_audit_log SET detalle = '{"pwned":true}'::jsonb
       WHERE accion = 'login' RETURNING id $$,
    'authenticated NO puede UPDATE admin_audit_log (inmutable desde cliente)'
);

-- Intento de DELETE: idem.
SELECT is_empty(
    $$ DELETE FROM public.admin_audit_log
       WHERE accion = 'login' RETURNING id $$,
    'authenticated NO puede DELETE admin_audit_log (inmutable desde cliente)'
);

-- SELECT sí funciona para admin.
SELECT ok(
    (SELECT count(*)::int FROM public.admin_audit_log) >= 1,
    'authenticated puede SELECT (ve los registros)'
);

-- ====== Comportamiento: anon no tiene EXECUTE sobre la RPC ======
-- Verificamos vía metadata (has_function_privilege) en vez de llamar la función,
-- para evitar un edge case donde la llamada desde anon con claims residuales
-- colgaba la conexión (ver commit history).

SELECT ok(
    NOT has_function_privilege(
        'anon',
        'public.log_admin_action(public.audit_accion, text, uuid, jsonb, inet, text)',
        'execute'
    ),
    'anon NO tiene EXECUTE sobre log_admin_action (solo authenticated)'
);

SELECT ok(
    has_function_privilege(
        'authenticated',
        'public.log_admin_action(public.audit_accion, text, uuid, jsonb, inet, text)',
        'execute'
    ),
    'authenticated SÍ tiene EXECUTE sobre log_admin_action'
);

SELECT * FROM finish();
ROLLBACK;
