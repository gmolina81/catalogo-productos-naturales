-- Migración: `productos_negocio.precio_venta` pasa de NOT NULL a nullable.
-- Spec: SPEC §4.1 (actualizado en v1.6).
-- Motivación: el seed inicial del Excel (Fase 1.4) trae 18 packs sin precio.
-- La decisión §9.1 dice que se importan con `activo = false` hasta que el
-- admin complete el precio. Para representar ese estado, precio_venta debe
-- poder ser NULL.

alter table public.productos_negocio
    alter column precio_venta drop not null;
