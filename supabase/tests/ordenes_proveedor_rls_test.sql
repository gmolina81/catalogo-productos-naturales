-- Tests para la tabla `ordenes_proveedor` (orden de compra consolidada).
-- Spec: SPEC §4.1 (estructura), §6.4 (admin-only), §5.4.3 (cómo se consolida).
-- Estándar: CLAUDE.md §6.3.

BEGIN;

SELECT plan(14);

-- ====== Estructura ======

SELECT has_type('public', 'estado_orden_proveedor',
    'enum estado_orden_proveedor existe');

SELECT has_table('public', 'ordenes_proveedor', 'tabla ordenes_proveedor existe');

SELECT columns_are(
    'public', 'ordenes_proveedor',
    ARRAY['id', 'numero', 'id_proveedor', 'estado', 'generada_por',
          'fecha_creacion', 'ids_pedidos_incluidos', 'detalle', 'total'],
    'ordenes_proveedor tiene las 9 columnas de SPEC §4.1'
);

SELECT col_is_pk('public', 'ordenes_proveedor', 'id', 'id es PK');

SELECT fk_ok(
    'public', 'ordenes_proveedor', 'id_proveedor',
    'public', 'proveedores', 'id',
    'id_proveedor es FK a proveedores.id'
);

SELECT fk_ok(
    'public', 'ordenes_proveedor', 'generada_por',
    'auth', 'users', 'id',
    'generada_por es FK a auth.users.id'
);

SELECT col_not_null('public', 'ordenes_proveedor', 'id_proveedor',
    'id_proveedor NOT NULL');
SELECT col_not_null('public', 'ordenes_proveedor', 'estado',
    'estado NOT NULL');

SELECT ok(
    (SELECT relrowsecurity FROM pg_class
     WHERE oid = 'public.ordenes_proveedor'::regclass),
    'RLS habilitado en ordenes_proveedor'
);

-- ====== Fixtures ======

INSERT INTO auth.users (id, is_sso_user, is_anonymous)
VALUES ('77777777-7777-7777-7777-777777777777', false, false);

INSERT INTO public.ordenes_proveedor (id_proveedor, generada_por, total, detalle)
SELECT id, '77777777-7777-7777-7777-777777777777', 5000,
       '[{"codigo_externo":"nuez|10kg","bultos_a_pedir":2,"precio_bulto":2500}]'::jsonb
FROM public.proveedores WHERE nombre = 'New Garden';

-- ====== Comportamiento: anon ======

SET LOCAL ROLE anon;

SELECT is_empty(
    $$ SELECT id FROM public.ordenes_proveedor $$,
    'anon no puede SELECT en ordenes_proveedor'
);

SELECT throws_ok(
    $$ INSERT INTO public.ordenes_proveedor (id_proveedor, generada_por)
       VALUES ('00000000-0000-0000-0000-000000000000',
               '77777777-7777-7777-7777-777777777777') $$,
    '42501',
    NULL,
    'anon no puede INSERT en ordenes_proveedor'
);

-- ====== Comportamiento: authenticated (admin) ======

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" TO
    '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';

SELECT ok(
    (SELECT count(*)::int FROM public.ordenes_proveedor) >= 1,
    'authenticated ve las órdenes'
);

SELECT lives_ok(
    $$ UPDATE public.ordenes_proveedor SET estado = 'enviada'
       WHERE generada_por = '77777777-7777-7777-7777-777777777777' $$,
    'authenticated puede cambiar estado (borrador → enviada)'
);

SELECT lives_ok(
    $$ INSERT INTO public.ordenes_proveedor (id_proveedor, generada_por, total)
       SELECT id, '77777777-7777-7777-7777-777777777777', 1000
       FROM public.proveedores WHERE nombre = 'New Garden' $$,
    'authenticated puede INSERT nueva orden'
);

SELECT * FROM finish();
ROLLBACK;
