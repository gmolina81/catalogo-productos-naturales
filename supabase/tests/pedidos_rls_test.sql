-- Tests para la tabla `pedidos`.
-- Spec: SPEC §4.1 (estructura), §6.4 (anon NO accede directo a la tabla; admin SELECT/UPDATE).
-- El checkout público usa la RPC `crear_pedido` (ver crear_pedido_rpc_test.sql).
-- Estándar: CLAUDE.md §6.3.

BEGIN;

SELECT plan(16);

-- ====== Estructura ======

SELECT has_type('public', 'estado_pedido', 'enum estado_pedido existe');
SELECT has_type('public', 'canal_pedido', 'enum canal_pedido existe');

SELECT has_table('public', 'pedidos', 'tabla pedidos existe');

SELECT columns_are(
    'public', 'pedidos',
    ARRAY[
        'id', 'numero', 'id_cliente', 'estado', 'canal',
        'total', 'notas_cliente', 'notas_admin',
        'fecha_pedido', 'fecha_entrega_estimada'
    ],
    'pedidos tiene las 10 columnas de SPEC §4.1'
);

SELECT col_is_pk('public', 'pedidos', 'id', 'id es PK');

SELECT fk_ok(
    'public', 'pedidos', 'id_cliente',
    'public', 'clientes', 'id',
    'id_cliente es FK a clientes.id'
);

SELECT col_not_null('public', 'pedidos', 'id_cliente', 'id_cliente NOT NULL');
SELECT col_not_null('public', 'pedidos', 'estado', 'estado NOT NULL');
SELECT col_not_null('public', 'pedidos', 'canal', 'canal NOT NULL');

SELECT ok(
    (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.pedidos'::regclass),
    'RLS habilitado en pedidos'
);

-- ====== Fixture: un cliente y un pedido como postgres ======

INSERT INTO public.clientes (id, nombre, telefono, email)
VALUES ('dddddddd-dddd-dddd-dddd-dddddddddddd',
        'Cliente Test', '1100000000', 'test@test.com');

INSERT INTO public.pedidos (id_cliente, estado, canal, total)
VALUES ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'pendiente', 'web', 1500);

-- ====== Comportamiento: anon (sin acceso directo) ======

SET LOCAL ROLE anon;

SELECT is_empty(
    $$ SELECT id FROM public.pedidos $$,
    'anon no puede SELECT directo en pedidos'
);

SELECT throws_ok(
    $$ INSERT INTO public.pedidos (id_cliente, estado, canal, total)
       VALUES ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'pendiente', 'web', 100) $$,
    '42501',
    NULL,
    'anon no puede INSERT directo (debe usar crear_pedido)'
);

SELECT is_empty(
    $$ UPDATE public.pedidos SET estado = 'cancelado' RETURNING id $$,
    'anon no puede UPDATE directo'
);

-- ====== Comportamiento: authenticated (admin) ======

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" TO
    '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT ok(
    (SELECT count(*)::int FROM public.pedidos) >= 1,
    'authenticated ve todos los pedidos'
);

SELECT lives_ok(
    $$ UPDATE public.pedidos SET estado = 'confirmado'
       WHERE id_cliente = 'dddddddd-dddd-dddd-dddd-dddddddddddd' $$,
    'authenticated puede UPDATE (cambiar estado)'
);

SELECT lives_ok(
    $$ UPDATE public.pedidos SET notas_admin = 'revisado'
       WHERE id_cliente = 'dddddddd-dddd-dddd-dddd-dddddddddddd' $$,
    'authenticated puede UPDATE notas_admin'
);

SELECT * FROM finish();
ROLLBACK;
