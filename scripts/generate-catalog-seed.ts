/**
 * Genera `supabase/seed.sql` completo desde el Excel del negocio.
 *
 * Uso: `npm run seed:generate`
 *
 * El script reescribe `supabase/seed.sql` ENTERO en cada corrida. Incluye:
 * 1. Bloque estático: proveedor único + usuario admin de prueba + identity.
 * 2. Bloque generado: 191 inserts en `productos_negocio` desde la hoja
 *    `catalog` del Excel (filas con nombre vacío se descartan).
 * 3. 191 placeholder en `mapeo_pack_bulto` (packs_por_bulto=1, merma_pct=0).
 *    El admin los cura en Fase 2.
 *
 * Re-ejecutar y commitear el SQL es la forma correcta de actualizar el
 * catálogo cuando cambia el Excel. Los UUIDs son aleatorios por corrida;
 * se commitean para mantener estabilidad entre regeneraciones.
 *
 * El bloque estático va inline en este script (no en un archivo separado)
 * porque la CLI de Supabase usa pgx para correr seed.sql y pgx no entiende
 * meta-comandos como `\ir`/`\i`. Un solo archivo es lo único que la
 * herramienta procesa correctamente.
 */

import { writeFile } from 'node:fs/promises'
import { randomUUID } from 'node:crypto'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import ExcelJS from 'exceljs'
import { normalizeRow, type RawCatalogRow } from '../src/lib/catalog-import.ts'

const PROJECT_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const EXCEL_PATH = resolve(PROJECT_ROOT, 'files/MM_productos_naturales.xlsx')
const OUTPUT_PATH = resolve(PROJECT_ROOT, 'supabase/seed.sql')
const SHEET_NAME = 'catalog'
const PLACEHOLDER_DESCRIPCION = 'Detallar con palabras claras'

// Bloque estático del seed (proveedor + admin de prueba + identity).
// Se incrusta en cada regeneración de seed.sql para mantener un único archivo
// que `supabase db reset` pueda procesar (la CLI usa pgx; no soporta `\ir`).
const SEED_STATIC = String.raw`-- ====== Proveedor único (New Garden). SPEC §1.5 ======
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

-- ====== Usuario admin de prueba (LOCAL/CI solamente) ======
-- Credenciales conocidas para tests de integración y E2E contra Supabase local.
-- En producción el admin se crea desde el dashboard de Supabase (otra cuenta, otro password).
-- Password: E2eAdminPass2026!  (cumple la política de SPEC §6.2)
--
-- Los campos confirmation_token, recovery_token, email_change_token_new y
-- email_change son text nullable sin default; GoTrue los escanea como string y
-- falla si son NULL. Hay que inicializarlos explícitamente en ''.
insert into auth.users (
    instance_id, id, aud, role, email,
    encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data,
    is_sso_user, is_anonymous,
    confirmation_token, recovery_token,
    email_change_token_new, email_change,
    created_at, updated_at
) values (
    '00000000-0000-0000-0000-000000000000',
    'aaaa1111-1111-1111-1111-111111111111',
    'authenticated', 'authenticated',
    'admin@test.local',
    crypt('E2eAdminPass2026!', gen_salt('bf', 10)),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    false, false,
    '', '', '', '',
    now(), now()
) on conflict (id) do nothing;

-- Identity row (Supabase moderna requiere una fila en auth.identities para
-- que signInWithPassword funcione con el provider 'email').
insert into auth.identities (
    id, user_id, identity_data, provider, provider_id,
    created_at, updated_at, last_sign_in_at
) values (
    gen_random_uuid(),
    'aaaa1111-1111-1111-1111-111111111111',
    jsonb_build_object(
        'sub', 'aaaa1111-1111-1111-1111-111111111111',
        'email', 'admin@test.local',
        'email_verified', true
    ),
    'email',
    'admin@test.local',
    now(), now(), now()
) on conflict (provider, provider_id) do nothing;
`

type Row = ReturnType<typeof normalizeRow>

async function main(): Promise<void> {
  const wb = new ExcelJS.Workbook()
  await wb.xlsx.readFile(EXCEL_PATH)
  const ws = wb.getWorksheet(SHEET_NAME)
  if (!ws) {
    throw new Error(`Hoja "${SHEET_NAME}" no encontrada en ${EXCEL_PATH}`)
  }

  const rows: Array<{ uuid: string; data: Row }> = []
  let warnings = 0
  let skipped = 0

  ws.eachRow({ includeEmpty: false }, (row, rowNum) => {
    if (rowNum === 1) return // header

    const nombreCell = row.getCell(2).value
    const nombreStr =
      nombreCell === null || nombreCell === undefined ? '' : String(nombreCell).trim()
    if (!nombreStr) {
      skipped++
      return
    }

    const descripcionCell = row.getCell(4).value
    const descripcionStr =
      descripcionCell === null || descripcionCell === undefined ? null : String(descripcionCell)
    const descripcion =
      descripcionStr && descripcionStr.trim() !== PLACEHOLDER_DESCRIPCION ? descripcionStr : null

    const precioCell = row.getCell(5).value
    const precio = typeof precioCell === 'number' ? precioCell : null

    // Las URLs vienen como hyperlink: { text, hyperlink, ... } o como string plano.
    const imagenCell = row.getCell(6).value
    let imagen: string | null = null
    if (imagenCell && typeof imagenCell === 'object' && 'hyperlink' in imagenCell) {
      imagen = String((imagenCell as { hyperlink?: string }).hyperlink ?? '').trim() || null
    } else if (typeof imagenCell === 'string') {
      imagen = imagenCell.trim() || null
    } else if (imagenCell !== null && imagenCell !== undefined) {
      // Otros tipos: fallback al string si tiene contenido razonable.
      imagen = String(imagenCell).trim() || null
    }

    const idCell = row.getCell(1).value
    const id = typeof idCell === 'number' || typeof idCell === 'string' ? idCell : null

    const raw: RawCatalogRow = {
      id,
      nombre: nombreStr,
      categoria: row.getCell(3).value === null ? null : String(row.getCell(3).value),
      descripcion,
      precio,
      imagen,
    }

    const data = normalizeRow(raw)

    if (data.nombre_publico.includes('�')) {
      console.warn(`[fila ${rowNum}] queda un caracter irrecuperable en: ${data.nombre_publico}`)
      warnings++
    }

    rows.push({ uuid: randomUUID(), data })
  })

  await writeFile(OUTPUT_PATH, buildSql(rows, { warnings, skipped }), 'utf-8')

  console.log(`✓ Generado ${OUTPUT_PATH}`)
  console.log(
    `  ${rows.length} productos | ${warnings} warnings de encoding | ${skipped} filas skipped (vacías)`,
  )
  const inactivos = rows.filter((r) => !r.data.activo).length
  console.log(`  ${inactivos} marcados activo=false (sin precio en el Excel)`)
}

function buildSql(
  rows: Array<{ uuid: string; data: Row }>,
  stats: { warnings: number; skipped: number },
): string {
  const header = [
    '-- GENERADO automáticamente por scripts/generate-catalog-seed.ts.',
    '-- NO EDITAR A MANO. Re-ejecutar `npm run seed:generate` cuando cambie el Excel.',
    `-- Fuente: files/MM_productos_naturales.xlsx (hoja "${SHEET_NAME}")`,
    `-- Última regeneración: ${new Date().toISOString()}`,
    `-- ${rows.length} productos | ${stats.warnings} warnings de encoding | ${stats.skipped} filas vacías`,
    '',
    SEED_STATIC,
    '-- ====== productos_negocio (catálogo del Excel) ======',
    'insert into public.productos_negocio',
    '    (id, nombre_publico, categoria, descripcion, presentacion,',
    '     precio_venta, precio_modo, markup_pct, imagen, activo,',
    '     id_producto_proveedor)',
    'values',
  ]

  const productLines = rows.map(({ uuid, data }, i) => {
    const sep = i === rows.length - 1 ? ';' : ','
    return (
      `    (${q(uuid)}, ${q(data.nombre_publico)}, ${q(data.categoria)}, ` +
      `${q(data.descripcion)}, ${q(data.presentacion)}, ${num(data.precio_venta)}, ` +
      `${q(data.precio_modo)}, ${data.markup_pct}, ${q(data.imagen)}, ${data.activo}, NULL)${sep}`
    )
  })

  const mapeoHeader = [
    '',
    '-- ====== mapeo_pack_bulto (placeholder, admin cura en Fase 2) ======',
    'insert into public.mapeo_pack_bulto (id_producto_negocio, packs_por_bulto, merma_pct)',
    'values',
  ]

  const mapeoLines = rows.map(({ uuid }, i) => {
    const sep = i === rows.length - 1 ? ';' : ','
    return `    (${q(uuid)}, 1, 0)${sep}`
  })

  return [...header, ...productLines, ...mapeoHeader, ...mapeoLines, ''].join('\n')
}

function q(value: string | null): string {
  if (value === null) return 'NULL'
  return `'${value.replace(/'/g, "''")}'`
}

function num(value: number | null): string {
  return value === null ? 'NULL' : String(value)
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
