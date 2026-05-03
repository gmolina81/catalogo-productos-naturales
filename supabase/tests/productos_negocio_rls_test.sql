-- Tests para la tabla `productos_negocio` (oferta curada del negocio).
-- Spec: SPEC §4.1 (estructura), §6.4 (RLS mixto: público si activo=true, resto admin).
-- Decisiones cerradas §9.1: default markup_sobre_costo con markup_pct=20.
-- FK id_producto_proveedor nullable (SPEC v1.3).
-- Estándar: CLAUDE.md §6.3.

BEGIN;

SELECT plan(18);

-- ====== Estructura ======

SELECT has_type('public', 'precio_modo', 'enum public.precio_modo existe');

SELECT has_table('public', 'productos_negocio', 'tabla productos_negocio existe');

SELECT columns_are(
    'public', 'productos_negocio',
    ARRAY[
        'id',
        'id_producto_proveedor',
        'nombre_publico',
        'categoria',
        'descripcion',
        'presentacion',
        'precio_venta',
        'precio_modo',
        'markup_pct',
        'imagen',
        'activo',
        'created_at',
        'updated_at'
    ],
    'productos_negocio tiene las 13 columnas de SPEC §4.1'
);

SELECT col_is_pk('public', 'productos_negocio', 'id', 'id es PK');

SELECT fk_ok(
    'public', 'productos_negocio', 'id_producto_proveedor',
    'public', 'productos_proveedor', 'id',
    'id_producto_proveedor es FK a productos_proveedor.id'
);

SELECT col_is_null(
    'public', 'productos_negocio', 'id_producto_proveedor',
    'id_producto_proveedor es nullable (SPEC v1.3)'
);

SELECT col_not_null('public', 'productos_negocio', 'nombre_publico',
    'nombre_publico NOT NULL');
SELECT col_is_null(
    'public', 'productos_negocio', 'precio_venta',
    'precio_venta es nullable (Fase 1.4 carga packs sin precio con activo=false; SPEC §4.1)'
);

-- ====== Seguridad ======

SELECT ok(
    (SELECT relrowsecurity FROM pg_class
     WHERE oid = 'public.productos_negocio'::regclass),
    'RLS habilitado en productos_negocio'
);

-- ====== Fixtures: 2 packs, uno activo y uno inactivo ======
-- Limpiar el seed que carga el catálogo del Excel (191 packs) para que las
-- aserciones de conteo se midan solo contra las filas que insertamos acá.
-- TRUNCATE corre dentro de la transacción del test; ROLLBACK al final restaura.
TRUNCATE public.mapeo_pack_bulto, public.productos_negocio CASCADE;

INSERT INTO public.productos_negocio
    (id, nombre_publico, categoria, presentacion, precio_venta, activo)
VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
     'Pack Activo', 'Frutos Secos', '1kg', 1000, true),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
     'Pack Inactivo', 'Frutos Secos', '1kg', 2000, false);

-- Default de markup_sobre_costo con 20 (decisión §9.1)
SELECT is(
    (SELECT markup_pct FROM public.productos_negocio
     WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
    20::numeric,
    'markup_pct tiene default 20 (decisión §9.1)'
);

SELECT is(
    (SELECT precio_modo::text FROM public.productos_negocio
     WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
    'markup_sobre_costo',
    'precio_modo tiene default markup_sobre_costo (decisión §9.1)'
);

-- ====== Comportamiento: anon ======

SET LOCAL ROLE anon;

-- Anon SOLO ve productos activos
SELECT results_eq(
    $$ SELECT nombre_publico FROM public.productos_negocio ORDER BY 1 $$,
    $$ VALUES ('Pack Activo'::text) $$,
    'anon ve SOLO productos activos (Pack Inactivo está oculto)'
);

SELECT throws_ok(
    $$ INSERT INTO public.productos_negocio
       (nombre_publico, categoria, presentacion, precio_venta)
       VALUES ('Hacker', 'X', 'X', 1) $$,
    '42501',
    NULL,
    'anon no puede INSERT en productos_negocio'
);

-- ====== Comportamiento: authenticated (v1 = admin) ======

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" TO
    '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

-- Admin ve TODOS (incluyendo inactivos)
SELECT is(
    (SELECT count(*)::int FROM public.productos_negocio),
    2,
    'authenticated ve todos los packs (activos e inactivos)'
);

SELECT lives_ok(
    $$ INSERT INTO public.productos_negocio
       (nombre_publico, categoria, presentacion, precio_venta, activo)
       VALUES ('Pack Nuevo', 'Frutas', '500g', 1500, true) $$,
    'authenticated puede INSERT'
);

-- updated_at trigger: cambia cuando hay UPDATE
RESET ROLE;

-- Forzar un tiempo anterior para el updated_at y verificar que el UPDATE lo renueva.
UPDATE public.productos_negocio
   SET updated_at = now() - interval '1 hour'
 WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" TO
    '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

UPDATE public.productos_negocio
   SET nombre_publico = 'Pack Activo v2'
 WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

SELECT ok(
    (SELECT updated_at FROM public.productos_negocio
     WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') > now() - interval '1 minute',
    'trigger set_updated_at actualiza updated_at en cada UPDATE'
);

SELECT lives_ok(
    $$ DELETE FROM public.productos_negocio
       WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
    'authenticated puede DELETE (soft delete se maneja vía activo, no FK)'
);

-- id_producto_proveedor = NULL debe permitirse (seed del Excel sin link al proveedor)
SELECT lives_ok(
    $$ INSERT INTO public.productos_negocio
       (nombre_publico, categoria, presentacion, precio_venta, id_producto_proveedor)
       VALUES ('Sin proveedor aún', 'X', '1kg', 100, NULL) $$,
    'authenticated puede INSERT con id_producto_proveedor = NULL (seed Fase 1)'
);

SELECT * FROM finish();
ROLLBACK;
