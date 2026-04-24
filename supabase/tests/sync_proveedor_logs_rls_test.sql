-- Tests para la tabla `sync_proveedor_logs` (auditoría de sincronización).
-- Spec: SPEC §4.1 (estructura), §5.3.3 (flujo de sync), §6.4 (admin-only).
-- Estándar: CLAUDE.md §6.3.

BEGIN;

SELECT plan(16);

-- ====== Estructura ======

SELECT has_type('public', 'origen_sync', 'enum origen_sync existe');
SELECT has_type('public', 'estado_sync', 'enum estado_sync existe');

SELECT has_table('public', 'sync_proveedor_logs',
    'tabla sync_proveedor_logs existe');

SELECT columns_are(
    'public', 'sync_proveedor_logs',
    ARRAY['id', 'id_proveedor', 'ejecutado_en', 'ejecutado_por',
          'origen', 'cambios_detectados', 'estado',
          'aplicado_en', 'resumen'],
    'sync_proveedor_logs tiene las 9 columnas de SPEC §4.1'
);

SELECT col_is_pk('public', 'sync_proveedor_logs', 'id', 'id es PK');

SELECT fk_ok(
    'public', 'sync_proveedor_logs', 'id_proveedor',
    'public', 'proveedores', 'id',
    'id_proveedor es FK a proveedores.id'
);

SELECT fk_ok(
    'public', 'sync_proveedor_logs', 'ejecutado_por',
    'auth', 'users', 'id',
    'ejecutado_por es FK a auth.users.id'
);

-- ejecutado_por es nullable (puede ser null si corre un cron)
SELECT col_is_null(
    'public', 'sync_proveedor_logs', 'ejecutado_por',
    'ejecutado_por es nullable (null cuando corre un cron, SPEC §4.1)'
);

SELECT col_not_null('public', 'sync_proveedor_logs', 'id_proveedor',
    'id_proveedor NOT NULL');
SELECT col_not_null('public', 'sync_proveedor_logs', 'origen',
    'origen NOT NULL');
SELECT col_not_null('public', 'sync_proveedor_logs', 'estado',
    'estado NOT NULL');

SELECT ok(
    (SELECT relrowsecurity FROM pg_class
     WHERE oid = 'public.sync_proveedor_logs'::regclass),
    'RLS habilitado en sync_proveedor_logs'
);

-- ====== Fixture ======

INSERT INTO auth.users (id, is_sso_user, is_anonymous)
VALUES ('88888888-8888-8888-8888-888888888888', false, false);

INSERT INTO public.sync_proveedor_logs (id_proveedor, ejecutado_por, origen, cambios_detectados, resumen)
SELECT id, '88888888-8888-8888-8888-888888888888', 'manual',
       '[{"tipo":"precio","codigo_externo":"nuez|10kg","antes":14000,"despues":14800}]'::jsonb,
       '{"nuevos":0,"precios":1,"bajas":0,"otros":0}'::jsonb
FROM public.proveedores WHERE nombre = 'New Garden';

-- ====== Comportamiento: anon ======

SET LOCAL ROLE anon;

SELECT is_empty(
    $$ SELECT id FROM public.sync_proveedor_logs $$,
    'anon no puede SELECT en sync_proveedor_logs'
);

SELECT throws_ok(
    $$ INSERT INTO public.sync_proveedor_logs
       (id_proveedor, origen)
       VALUES ('00000000-0000-0000-0000-000000000000', 'manual') $$,
    '42501',
    NULL,
    'anon no puede INSERT en sync_proveedor_logs'
);

-- ====== Comportamiento: authenticated (admin) ======

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" TO
    '{"sub":"88888888-8888-8888-8888-888888888888","role":"authenticated"}';

SELECT ok(
    (SELECT count(*)::int FROM public.sync_proveedor_logs) >= 1,
    'authenticated ve los logs de sync'
);

-- Aplicar un sync: actualizar estado a "aplicado" y setear aplicado_en
SELECT lives_ok(
    $$ UPDATE public.sync_proveedor_logs
       SET estado = 'aplicado', aplicado_en = now()
       WHERE ejecutado_por = '88888888-8888-8888-8888-888888888888' $$,
    'authenticated puede marcar un sync como aplicado'
);

SELECT * FROM finish();
ROLLBACK;
