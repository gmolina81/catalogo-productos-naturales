-- Tests para la tabla `mapeo_pack_bulto` (cuántos packs por bulto, merma).
-- Spec: SPEC §4.1 (estructura) y §6.4 (todo solo admin autenticado).
-- Relación 1:1 con productos_negocio (UNIQUE en id_producto_negocio).
-- Estándar: CLAUDE.md §6.3.

BEGIN;

SELECT plan(11);

-- ====== Estructura ======

SELECT has_table('public', 'mapeo_pack_bulto', 'tabla mapeo_pack_bulto existe');

SELECT columns_are(
    'public', 'mapeo_pack_bulto',
    ARRAY['id', 'id_producto_negocio', 'packs_por_bulto', 'merma_pct', 'notas'],
    'mapeo_pack_bulto tiene las 5 columnas de SPEC §4.1'
);

SELECT col_is_pk('public', 'mapeo_pack_bulto', 'id', 'id es PK');

SELECT fk_ok(
    'public', 'mapeo_pack_bulto', 'id_producto_negocio',
    'public', 'productos_negocio', 'id',
    'id_producto_negocio es FK a productos_negocio.id'
);

SELECT col_is_unique(
    'public', 'mapeo_pack_bulto', ARRAY['id_producto_negocio'],
    'id_producto_negocio es UNIQUE (relación 1:1 con productos_negocio)'
);

SELECT col_not_null('public', 'mapeo_pack_bulto', 'packs_por_bulto',
    'packs_por_bulto NOT NULL');
SELECT col_not_null('public', 'mapeo_pack_bulto', 'merma_pct',
    'merma_pct NOT NULL');

SELECT ok(
    (SELECT relrowsecurity FROM pg_class
     WHERE oid = 'public.mapeo_pack_bulto'::regclass),
    'RLS habilitado en mapeo_pack_bulto'
);

-- ====== Fixtures ======
-- Limpiar el seed del Excel (191 packs + 191 mapeos) antes de insertar
-- los fixtures de este test. TRUNCATE en la transacción del test;
-- ROLLBACK al final restaura.
TRUNCATE public.mapeo_pack_bulto, public.productos_negocio CASCADE;

-- Un pack y su mapeo.
INSERT INTO public.productos_negocio
    (id, nombre_publico, categoria, presentacion, precio_venta, activo)
VALUES
    ('cccccccc-cccc-cccc-cccc-cccccccccccc',
     'Nueces 1kg', 'Frutos Secos', '1kg', 1000, true);

INSERT INTO public.mapeo_pack_bulto
    (id_producto_negocio, packs_por_bulto, merma_pct)
VALUES
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', 5, 0);

-- ====== Comportamiento: anon ======

SET LOCAL ROLE anon;

SELECT is_empty(
    $$ SELECT id FROM public.mapeo_pack_bulto $$,
    'anon no ve nada de mapeo_pack_bulto'
);

SELECT throws_ok(
    $$ INSERT INTO public.mapeo_pack_bulto
       (id_producto_negocio, packs_por_bulto, merma_pct)
       VALUES ('cccccccc-cccc-cccc-cccc-cccccccccccc', 1, 0) $$,
    '42501',
    NULL,
    'anon no puede INSERT en mapeo_pack_bulto'
);

-- ====== Comportamiento: authenticated ======

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" TO
    '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT ok(
    (SELECT count(*)::int FROM public.mapeo_pack_bulto) = 1,
    'authenticated ve el mapeo del pack fixture'
);

SELECT * FROM finish();
ROLLBACK;
