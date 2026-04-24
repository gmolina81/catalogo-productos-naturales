-- Seed para desarrollo local.
-- Se ejecuta después de todas las migraciones cuando corrés `supabase db reset`.
-- NO incluir datos reales del negocio acá; solo fixtures estables para tests manuales.

-- Proveedor único (New Garden). SPEC §1.5.
-- sheet_id corresponde a la URL pública compartida por el negocio.
insert into public.proveedores (nombre, sheet_id, sheet_range, contacto_whatsapp, contacto_email, activo)
values (
    'New Garden',
    '1O-zrDpH7-vKnegG38pm8u4qIoY9NySsJD2T8WGRjbtk',
    null,
    '1134632133',
    null,
    true
)
on conflict do nothing;
