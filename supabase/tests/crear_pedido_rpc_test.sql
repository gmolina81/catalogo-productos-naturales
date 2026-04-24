-- Tests para la RPC `crear_pedido` (checkout público atómico).
-- Spec: SPEC §5.2 (flujo de checkout), §6.4 (clientes/pedidos/pedido_items
-- no se tocan directo desde anon; todo el checkout pasa por esta RPC).
-- La función es SECURITY DEFINER: bypassa RLS y valida inputs server-side.
-- Estándar: CLAUDE.md §6.3.

BEGIN;

SELECT plan(14);

-- ====== Existencia ======

SELECT has_function(
    'public', 'crear_pedido',
    ARRAY['text', 'text', 'text', 'jsonb', 'text', 'text', 'date'],
    'función public.crear_pedido(email, nombre, telefono, items jsonb, direccion, notas, fecha) existe'
);

-- ====== Fixtures: 2 packs activos y 1 inactivo ======

INSERT INTO public.productos_negocio
    (id, nombre_publico, categoria, presentacion, precio_venta, activo)
VALUES
    ('11111111-0000-0000-0000-000000000001',
     'Pack A 1kg', 'Frutos Secos', '1kg', 1000, true),
    ('11111111-0000-0000-0000-000000000002',
     'Pack B 500g', 'Frutos Secos', '500g', 600, true),
    ('11111111-0000-0000-0000-000000000003',
     'Pack Inactivo', 'Frutos Secos', '1kg', 999, false);

-- ====== Comportamiento: anon llama a la RPC ======

SET LOCAL ROLE anon;

-- Caso 1: happy path — crea cliente, pedido, items; calcula total.
SELECT lives_ok(
    $$ SELECT public.crear_pedido(
        'cliente1@test.com', 'Juan Cliente', '5491100000000',
        '[{"id_producto_negocio":"11111111-0000-0000-0000-000000000001","cantidad":2},
          {"id_producto_negocio":"11111111-0000-0000-0000-000000000002","cantidad":3}]'::jsonb,
        NULL, NULL, NULL
    ) $$,
    'anon puede llamar crear_pedido con items válidos'
);

-- Verificar como postgres
RESET ROLE;

SELECT is(
    (SELECT count(*)::int FROM public.clientes WHERE email = 'cliente1@test.com'),
    1,
    'crear_pedido creó el cliente'
);

-- total = 2*1000 + 3*600 = 3800
SELECT is(
    (SELECT total FROM public.pedidos p
     JOIN public.clientes c ON c.id = p.id_cliente
     WHERE c.email = 'cliente1@test.com'),
    3800::numeric,
    'total del pedido es la suma de subtotales (2*1000 + 3*600 = 3800)'
);

SELECT is(
    (SELECT count(*)::int FROM public.pedido_items pi
     JOIN public.pedidos p ON p.id = pi.id_pedido
     JOIN public.clientes c ON c.id = p.id_cliente
     WHERE c.email = 'cliente1@test.com'),
    2,
    'pedido tiene 2 items'
);

SELECT is(
    (SELECT estado::text FROM public.pedidos p
     JOIN public.clientes c ON c.id = p.id_cliente
     WHERE c.email = 'cliente1@test.com'),
    'pendiente',
    'pedido arranca en estado pendiente'
);

SELECT is(
    (SELECT canal::text FROM public.pedidos p
     JOIN public.clientes c ON c.id = p.id_cliente
     WHERE c.email = 'cliente1@test.com'),
    'web',
    'canal del pedido creado vía RPC es web'
);

-- Caso 2: segundo pedido con el mismo email reutiliza el cliente (upsert)
SET LOCAL ROLE anon;

SELECT lives_ok(
    $$ SELECT public.crear_pedido(
        'cliente1@test.com', 'Juan C.', '5491100000000',
        '[{"id_producto_negocio":"11111111-0000-0000-0000-000000000001","cantidad":1}]'::jsonb,
        NULL, NULL, NULL
    ) $$,
    'anon puede llamar crear_pedido de nuevo con mismo email'
);

RESET ROLE;

SELECT is(
    (SELECT count(*)::int FROM public.clientes WHERE email = 'cliente1@test.com'),
    1,
    'segundo pedido no duplicó el cliente (upsert por email)'
);

SELECT is(
    (SELECT count(*)::int FROM public.pedidos p
     JOIN public.clientes c ON c.id = p.id_cliente
     WHERE c.email = 'cliente1@test.com'),
    2,
    'segundo pedido se creó (2 pedidos para el mismo cliente)'
);

-- ====== Validaciones ======

SET LOCAL ROLE anon;

-- items vacío
SELECT throws_ok(
    $$ SELECT public.crear_pedido(
        'c2@test.com', 'X', '1234567',
        '[]'::jsonb, NULL, NULL, NULL
    ) $$,
    '22023',
    NULL,
    'items vacío → 22023'
);

-- cantidad <= 0
SELECT throws_ok(
    $$ SELECT public.crear_pedido(
        'c2@test.com', 'X', '1234567',
        '[{"id_producto_negocio":"11111111-0000-0000-0000-000000000001","cantidad":0}]'::jsonb,
        NULL, NULL, NULL
    ) $$,
    '22023',
    NULL,
    'cantidad <= 0 → 22023'
);

-- producto inactivo
SELECT throws_ok(
    $$ SELECT public.crear_pedido(
        'c2@test.com', 'X', '1234567',
        '[{"id_producto_negocio":"11111111-0000-0000-0000-000000000003","cantidad":1}]'::jsonb,
        NULL, NULL, NULL
    ) $$,
    '22023',
    NULL,
    'producto inactivo → 22023'
);

-- producto inexistente
SELECT throws_ok(
    $$ SELECT public.crear_pedido(
        'c2@test.com', 'X', '1234567',
        '[{"id_producto_negocio":"00000000-0000-0000-0000-000000000000","cantidad":1}]'::jsonb,
        NULL, NULL, NULL
    ) $$,
    '22023',
    NULL,
    'producto inexistente → 22023'
);

SELECT * FROM finish();
ROLLBACK;
