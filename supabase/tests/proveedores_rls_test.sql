-- Tests para la tabla `proveedores` y sus políticas RLS.
-- Spec: SPEC §4.1 (estructura), §6.4 (política: solo admin autenticado puede todo).
-- Estándar: CLAUDE.md §6.3 (mínimo 3 tests por política: anon no puede, admin sí puede, edge cases).

BEGIN;

SELECT plan(12);

-- ====== Estructura ======

SELECT has_table('public', 'proveedores', 'tabla proveedores existe');

SELECT columns_are(
    'public', 'proveedores',
    ARRAY[
        'id',
        'nombre',
        'sheet_id',
        'sheet_range',
        'contacto_whatsapp',
        'contacto_email',
        'activo',
        'created_at'
    ],
    'proveedores tiene las columnas definidas en SPEC §4.1 (sin extras)'
);

SELECT col_is_pk('public', 'proveedores', 'id', 'id es PK de proveedores');

SELECT col_not_null('public', 'proveedores', 'nombre', 'nombre es NOT NULL');
SELECT col_not_null('public', 'proveedores', 'sheet_id', 'sheet_id es NOT NULL');

-- ====== Seguridad ======

SELECT ok(
    (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.proveedores'::regclass),
    'RLS habilitado en proveedores'
);

SELECT isnt_empty(
    $$ SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'proveedores' $$,
    'proveedores tiene al menos una policy RLS'
);

-- ====== Comportamiento: anon ======

SET LOCAL ROLE anon;

SELECT is_empty(
    $$ SELECT id FROM public.proveedores $$,
    'anon no ve ninguna fila de proveedores (RLS bloquea SELECT)'
);

SELECT throws_ok(
    $$ INSERT INTO public.proveedores (nombre, sheet_id, contacto_whatsapp) VALUES ('hacker', 'x', '0') $$,
    '42501',
    NULL,
    'anon no puede INSERT en proveedores'
);

-- ====== Comportamiento: authenticated (en v1 implica admin) ======

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT ok(
    (SELECT count(*)::int FROM public.proveedores) >= 1,
    'authenticated puede SELECT (ve al menos la fila única del seed)'
);

SELECT lives_ok(
    $$ INSERT INTO public.proveedores (nombre, sheet_id, contacto_whatsapp)
       VALUES ('Test Provider', 'test-sheet', '5491100000000') $$,
    'authenticated puede INSERT en proveedores'
);

SELECT lives_ok(
    $$ UPDATE public.proveedores SET activo = false WHERE nombre = 'Test Provider' $$,
    'authenticated puede UPDATE en proveedores'
);

SELECT * FROM finish();
ROLLBACK;
