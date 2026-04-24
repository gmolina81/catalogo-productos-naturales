-- Tests para la tabla `clientes` y la RPC `upsert_cliente`.
-- Spec: SPEC §4.1 (estructura), §5.2 (upsert por email en checkout),
--       §6.4 (anon NO accede a la tabla directamente; admin SELECT/UPDATE/DELETE).
-- Diseño: anon usa SOLO la RPC (SECURITY DEFINER) — no recibe grants directos de UPDATE.
-- Estándar: CLAUDE.md §6.3.

BEGIN;

SELECT plan(18);

-- ====== Estructura ======

SELECT has_table('public', 'clientes', 'tabla clientes existe');

SELECT columns_are(
    'public', 'clientes',
    ARRAY['id', 'nombre', 'telefono', 'email', 'direccion', 'notas', 'created_at'],
    'clientes tiene las 7 columnas de SPEC §4.1'
);

SELECT col_is_pk('public', 'clientes', 'id', 'id es PK');
SELECT col_is_unique('public', 'clientes', ARRAY['email'], 'email es UNIQUE (clave natural)');
SELECT col_not_null('public', 'clientes', 'nombre', 'nombre NOT NULL');
SELECT col_not_null('public', 'clientes', 'telefono', 'telefono NOT NULL');
SELECT col_not_null('public', 'clientes', 'email', 'email NOT NULL');

-- ====== RLS + RPC ======

SELECT ok(
    (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.clientes'::regclass),
    'RLS habilitado en clientes'
);

SELECT has_function(
    'public', 'upsert_cliente',
    ARRAY['text', 'text', 'text', 'text', 'text'],
    'función public.upsert_cliente(email, nombre, telefono, direccion, notas) existe'
);

-- ====== Fixture: 1 cliente pre-existente (insertado como postgres) ======

INSERT INTO public.clientes (nombre, telefono, email, direccion, notas)
VALUES ('Existente', '1111111', 'existente@test.com', 'Calle 1', 'VIP');

-- ====== Comportamiento: anon directo sobre la tabla → bloqueado ======

SET LOCAL ROLE anon;

SELECT is_empty(
    $$ SELECT id FROM public.clientes $$,
    'anon no puede SELECT directo en clientes'
);

SELECT throws_ok(
    $$ INSERT INTO public.clientes (nombre, telefono, email)
       VALUES ('Hack', '0', 'hack@test.com') $$,
    '42501',
    NULL,
    'anon no puede INSERT directo (debe usar la RPC)'
);

-- UPDATE sin policy: RLS filtra, 0 filas afectadas, silencioso.
SELECT is_empty(
    $$ UPDATE public.clientes SET nombre = 'pwned'
       WHERE email = 'existente@test.com' RETURNING id $$,
    'anon no puede UPDATE directo'
);

-- ====== Comportamiento: anon vía RPC ======

-- Caso 1: nuevo email → INSERT
SELECT ok(
    public.upsert_cliente(
        'nuevo@test.com', 'Cliente Nuevo', '5491100000000', NULL, NULL
    ) IS NOT NULL,
    'anon puede crear cliente nuevo vía upsert_cliente'
);

-- Caso 2: email existente → UPDATE (nombre y teléfono se actualizan)
SELECT ok(
    public.upsert_cliente(
        'existente@test.com', 'Existente Renombrado', '2222222', NULL, NULL
    ) IS NOT NULL,
    'anon puede upsertar cliente existente vía upsert_cliente'
);

-- Validación: email inválido → error
SELECT throws_ok(
    $$ SELECT public.upsert_cliente(
        'no-es-email', 'X', '1234567', NULL, NULL
    ) $$,
    '22023',
    NULL,
    'upsert_cliente rechaza email inválido'
);

-- ====== Verificación cruzada como postgres ======

RESET ROLE;

-- El email existente ahora tiene el nombre actualizado, y dirección/notas preservadas.
SELECT results_eq(
    $$ SELECT nombre, direccion, notas FROM public.clientes
       WHERE email = 'existente@test.com' $$,
    $$ VALUES ('Existente Renombrado'::text, 'Calle 1'::text, 'VIP'::text) $$,
    'upsert preservó dirección/notas cuando el cliente pasó NULL'
);

-- ====== Comportamiento: authenticated (admin) ======

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" TO
    '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT ok(
    (SELECT count(*)::int FROM public.clientes) >= 2,
    'authenticated ve todos los clientes'
);

SELECT lives_ok(
    $$ DELETE FROM public.clientes WHERE email = 'nuevo@test.com' $$,
    'authenticated puede DELETE'
);

SELECT * FROM finish();
ROLLBACK;
