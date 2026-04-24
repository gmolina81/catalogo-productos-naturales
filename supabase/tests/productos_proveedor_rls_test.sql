-- Tests para la tabla `productos_proveedor` (snapshot de la Sheet).
-- Spec: SPEC §4.1 (estructura reescrita en v1.4: cada fila es una combinación
-- producto+presentación, con codigo_externo sintético y reemplaza_a para fusión manual).
-- RLS: SPEC §6.4 (todo solo admin autenticado).
-- Estándar: CLAUDE.md §6.3.

BEGIN;

SELECT plan(19);

-- ====== Estructura ======

SELECT has_type('public', 'estado_producto_proveedor',
    'enum public.estado_producto_proveedor existe');

SELECT has_table('public', 'productos_proveedor', 'tabla productos_proveedor existe');

SELECT columns_are(
    'public', 'productos_proveedor',
    ARRAY[
        'id',
        'id_proveedor',
        'codigo_externo',
        'nombre_base',
        'nombre_original',
        'presentacion',
        'categoria',
        'descripcion',
        'precio_bulto',
        'unidad_compra',
        'imagen',
        'estado',
        'ultima_sync',
        'reemplaza_a'
    ],
    'productos_proveedor tiene las 14 columnas de SPEC §4.1 (sin extras)'
);

SELECT col_is_pk('public', 'productos_proveedor', 'id', 'id es PK');

SELECT fk_ok(
    'public', 'productos_proveedor', 'id_proveedor',
    'public', 'proveedores', 'id',
    'id_proveedor es FK a proveedores.id'
);

SELECT fk_ok(
    'public', 'productos_proveedor', 'reemplaza_a',
    'public', 'productos_proveedor', 'id',
    'reemplaza_a es self-FK para fusión manual (§5.3.3)'
);

SELECT col_is_unique(
    'public', 'productos_proveedor', ARRAY['id_proveedor', 'codigo_externo'],
    'constraint único en (id_proveedor, codigo_externo)'
);

SELECT col_not_null('public', 'productos_proveedor', 'id_proveedor',
    'id_proveedor NOT NULL');
SELECT col_not_null('public', 'productos_proveedor', 'codigo_externo',
    'codigo_externo NOT NULL');
SELECT col_not_null('public', 'productos_proveedor', 'nombre_base',
    'nombre_base NOT NULL');
SELECT col_not_null('public', 'productos_proveedor', 'presentacion',
    'presentacion NOT NULL');

-- ====== Seguridad ======

SELECT ok(
    (SELECT relrowsecurity FROM pg_class
     WHERE oid = 'public.productos_proveedor'::regclass),
    'RLS habilitado en productos_proveedor'
);

SELECT isnt_empty(
    $$ SELECT policyname FROM pg_policies
       WHERE schemaname = 'public' AND tablename = 'productos_proveedor' $$,
    'productos_proveedor tiene al menos una policy RLS'
);

-- ====== Fixtures ======
-- Insertamos desde postgres (bypass RLS). El proveedor ya está seedeado.

INSERT INTO public.productos_proveedor
    (id_proveedor, codigo_externo, nombre_base, nombre_original,
     presentacion, categoria, precio_bulto, unidad_compra, estado)
SELECT id, 'nuez-mariposa|10kg', 'Nuez Mariposa',
       'Nuez Mariposa Extra Light 2026 ', '10KG', 'FRUTOS SECOS',
       14800, '10KG', 'activo'
FROM public.proveedores WHERE nombre = 'New Garden';

-- ====== Comportamiento: anon ======

SET LOCAL ROLE anon;

SELECT is_empty(
    $$ SELECT id FROM public.productos_proveedor $$,
    'anon no ve nada de productos_proveedor'
);

SELECT throws_ok(
    $$ INSERT INTO public.productos_proveedor
       (id_proveedor, codigo_externo, nombre_base, nombre_original,
        presentacion, categoria, estado)
       VALUES ('00000000-0000-0000-0000-000000000000',
               'hack|1kg', 'Hack', 'Hack', '1KG', 'X', 'activo') $$,
    '42501',
    NULL,
    'anon no puede INSERT en productos_proveedor'
);

-- ====== Comportamiento: authenticated (v1 = admin) ======

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" TO
    '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT ok(
    (SELECT count(*)::int FROM public.productos_proveedor) >= 1,
    'authenticated puede SELECT (ve el producto insertado como fixture)'
);

SELECT lives_ok(
    $$ INSERT INTO public.productos_proveedor
       (id_proveedor, codigo_externo, nombre_base, nombre_original,
        presentacion, categoria, precio_bulto, unidad_compra, estado)
       SELECT id, 'almendra|1kg', 'Almendra', 'Almendra Non Pareil 27/30',
              '1KG', 'FRUTOS SECOS', 18700, '1KG', 'activo'
       FROM public.proveedores WHERE nombre = 'New Garden' $$,
    'authenticated puede INSERT nuevas combinaciones producto+presentación'
);

SELECT lives_ok(
    $$ UPDATE public.productos_proveedor SET precio_bulto = 15300
       WHERE codigo_externo = 'nuez-mariposa|10kg' $$,
    'authenticated puede UPDATE precios'
);

SELECT throws_ok(
    $$ INSERT INTO public.productos_proveedor
       (id_proveedor, codigo_externo, nombre_base, nombre_original,
        presentacion, categoria, unidad_compra, estado)
       SELECT id, 'nuez-mariposa|10kg', 'Duplicado', 'Duplicado',
              '10KG', 'FRUTOS SECOS', '10KG', 'activo'
       FROM public.proveedores WHERE nombre = 'New Garden' $$,
    '23505',
    NULL,
    'no se pueden duplicar combinaciones (id_proveedor, codigo_externo)'
);

SELECT * FROM finish();
ROLLBACK;
