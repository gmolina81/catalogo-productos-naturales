-- Tests para la tabla `pedido_items`.
-- Spec: SPEC §4.1 (estructura: subtotal = cantidad * precio_unitario),
--       §6.4 (anon NO accede directo; admin SELECT/UPDATE).
-- Estándar: CLAUDE.md §6.3.

BEGIN;

SELECT plan(12);

-- ====== Estructura ======

SELECT has_table('public', 'pedido_items', 'tabla pedido_items existe');

SELECT columns_are(
    'public', 'pedido_items',
    ARRAY['id', 'id_pedido', 'id_producto_negocio', 'cantidad',
          'precio_unitario', 'subtotal'],
    'pedido_items tiene las 6 columnas de SPEC §4.1'
);

SELECT col_is_pk('public', 'pedido_items', 'id', 'id es PK');

SELECT fk_ok(
    'public', 'pedido_items', 'id_pedido',
    'public', 'pedidos', 'id',
    'id_pedido es FK a pedidos.id'
);

SELECT fk_ok(
    'public', 'pedido_items', 'id_producto_negocio',
    'public', 'productos_negocio', 'id',
    'id_producto_negocio es FK a productos_negocio.id'
);

SELECT col_not_null('public', 'pedido_items', 'cantidad', 'cantidad NOT NULL');
SELECT col_not_null('public', 'pedido_items', 'precio_unitario', 'precio_unitario NOT NULL');

SELECT ok(
    (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.pedido_items'::regclass),
    'RLS habilitado en pedido_items'
);

-- ====== Fixture: cliente + pedido + producto_negocio + item ======

INSERT INTO public.clientes (id, nombre, telefono, email)
VALUES ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
        'C', '1100000000', 'pitems@test.com');

INSERT INTO public.pedidos (id, id_cliente, estado, canal, total)
VALUES ('ffffffff-ffff-ffff-ffff-ffffffffffff',
        'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
        'pendiente', 'web', 0);

INSERT INTO public.productos_negocio (id, nombre_publico, categoria, presentacion, precio_venta)
VALUES ('99999999-9999-9999-9999-999999999999',
        'Nueces 1kg', 'Frutos Secos', '1kg', 500);

INSERT INTO public.pedido_items (id_pedido, id_producto_negocio, cantidad, precio_unitario)
VALUES ('ffffffff-ffff-ffff-ffff-ffffffffffff',
        '99999999-9999-9999-9999-999999999999',
        3, 500);

-- subtotal debe haber sido calculado automáticamente (GENERATED column)
SELECT is(
    (SELECT subtotal FROM public.pedido_items
     WHERE id_pedido = 'ffffffff-ffff-ffff-ffff-ffffffffffff'),
    1500::numeric,
    'subtotal se calcula automáticamente como cantidad * precio_unitario'
);

-- ====== Comportamiento: anon (sin acceso directo) ======

SET LOCAL ROLE anon;

SELECT is_empty(
    $$ SELECT id FROM public.pedido_items $$,
    'anon no puede SELECT directo en pedido_items'
);

SELECT throws_ok(
    $$ INSERT INTO public.pedido_items
       (id_pedido, id_producto_negocio, cantidad, precio_unitario)
       VALUES ('ffffffff-ffff-ffff-ffff-ffffffffffff',
               '99999999-9999-9999-9999-999999999999', 1, 500) $$,
    '42501',
    NULL,
    'anon no puede INSERT directo (debe usar crear_pedido)'
);

-- ====== Comportamiento: authenticated (admin) ======

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" TO
    '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT ok(
    (SELECT count(*)::int FROM public.pedido_items) >= 1,
    'authenticated ve todos los pedido_items'
);

SELECT * FROM finish();
ROLLBACK;
