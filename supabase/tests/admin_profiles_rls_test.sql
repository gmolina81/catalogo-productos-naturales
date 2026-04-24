-- Tests para la tabla `admin_profiles` y sus políticas RLS.
-- Spec: SPEC §4.1 (estructura) y §6.4 (policy: solo el propio admin lee/escribe su fila).
-- Estándar: CLAUDE.md §6.3.

BEGIN;

SELECT plan(14);

-- ====== Estructura ======

SELECT has_type('public', 'admin_rol', 'enum public.admin_rol existe');

SELECT has_table('public', 'admin_profiles', 'tabla admin_profiles existe');

SELECT columns_are(
    'public', 'admin_profiles',
    ARRAY['id', 'nombre', 'rol', 'activo', 'created_at'],
    'admin_profiles tiene las columnas definidas en SPEC §4.1 (sin extras)'
);

SELECT col_is_pk('public', 'admin_profiles', 'id', 'id es PK');

SELECT fk_ok(
    'public', 'admin_profiles', 'id',
    'auth', 'users', 'id',
    'id es FK a auth.users.id'
);

SELECT col_not_null('public', 'admin_profiles', 'nombre', 'nombre es NOT NULL');
SELECT col_not_null('public', 'admin_profiles', 'rol', 'rol es NOT NULL');

-- ====== Seguridad ======

SELECT ok(
    (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.admin_profiles'::regclass),
    'RLS habilitado en admin_profiles'
);

-- ====== Fixtures: dos usuarios fake y sus profiles (como postgres superuser) ======

INSERT INTO auth.users (id, is_sso_user, is_anonymous)
VALUES
    ('11111111-1111-1111-1111-111111111111', false, false),
    ('22222222-2222-2222-2222-222222222222', false, false);

INSERT INTO public.admin_profiles (id, nombre, rol, activo)
VALUES
    ('11111111-1111-1111-1111-111111111111', 'Admin Uno', 'admin', true),
    ('22222222-2222-2222-2222-222222222222', 'Admin Dos', 'admin', true);

-- ====== Comportamiento: anon ======

SET LOCAL ROLE anon;

SELECT is_empty(
    $$ SELECT id FROM public.admin_profiles $$,
    'anon no ve ninguna fila de admin_profiles'
);

SELECT throws_ok(
    $$ INSERT INTO public.admin_profiles (id, nombre, rol)
       VALUES ('33333333-3333-3333-3333-333333333333', 'Hacker', 'admin') $$,
    '42501',
    NULL,
    'anon no puede INSERT en admin_profiles'
);

-- ====== Comportamiento: authenticated como Admin Uno ======

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" TO
    '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

SELECT results_eq(
    $$ SELECT nombre FROM public.admin_profiles $$,
    $$ VALUES ('Admin Uno'::text) $$,
    'admin1 SOLO ve su propia fila'
);

SELECT lives_ok(
    $$ UPDATE public.admin_profiles SET nombre = 'Admin Uno renamed'
       WHERE id = '11111111-1111-1111-1111-111111111111' $$,
    'admin1 puede UPDATE su propia fila'
);

-- Intento de modificar la fila de admin2: RLS debe filtrar y no afectar ninguna fila.
SELECT is_empty(
    $$ UPDATE public.admin_profiles SET nombre = 'pwned'
       WHERE id = '22222222-2222-2222-2222-222222222222'
       RETURNING id $$,
    'admin1 NO puede UPDATE la fila de admin2 (RLS filtra)'
);

-- Verificar como postgres que admin2 no fue tocado.
RESET ROLE;

SELECT results_eq(
    $$ SELECT nombre FROM public.admin_profiles
       WHERE id = '22222222-2222-2222-2222-222222222222' $$,
    $$ VALUES ('Admin Dos'::text) $$,
    'la fila de admin2 quedó intacta después del intento de admin1'
);

SELECT * FROM finish();
ROLLBACK;
