/**
 * Helpers para importar el catálogo del negocio (SPEC §8 Fase 1.4).
 *
 * Responsabilidades:
 * - `fixEncoding`: repara mojibake en nombres del Excel original
 *   (caracteres reemplazados por `�`).
 * - `normalizeCategoria`: canoniza variantes de la misma categoría
 *   (case, plural/singular, espacios extra).
 * - `extractPresentacion`: separa "1 kg" trailing del nombre cuando aparece.
 * - `normalizeRow`: aplica las cuatro normalizaciones a una fila cruda
 *   y produce la forma que se inserta en `productos_negocio`.
 *
 * Fuente del catálogo: `files/MM_productos_naturales.xlsx` (hoja `catalog`).
 */

export type RawCatalogRow = {
  id: string | number | null
  nombre: string
  categoria: string | null
  descripcion: string | null
  precio: number | null
  imagen: string | null
}

export type NormalizedCatalogRow = {
  nombre_publico: string
  categoria: string
  descripcion: string | null
  presentacion: string
  precio_venta: number | null
  precio_modo: 'markup_sobre_costo'
  markup_pct: 20
  imagen: string | null
  activo: boolean
}

// ====== fixEncoding ======

// Pares observados al inspeccionar el Excel. Se aplican en orden, ambos cases.
// Si aparece un patrón nuevo, agregar acá; el sufijo `�` que sobrevive queda
// visible para que el admin lo detecte.
const ENCODING_FIXES: Array<[string, string]> = [
  ['Caj�', 'Cajú'],
  ['caj�', 'cajú'],
  ['Casta�a', 'Castaña'],
  ['casta�a', 'castaña'],
  ['Man�', 'Maní'],
  ['man�', 'maní'],
  ['Az�car', 'Azúcar'],
  ['az�car', 'azúcar'],
  ['S�samo', 'Sésamo'],
  ['s�samo', 'sésamo'],
  ['Ch�a', 'Chía'],
  ['ch�a', 'chía'],
  ['Ar�ndano', 'Arándano'],
  ['ar�ndano', 'arándano'],
  ['Org�nico', 'Orgánico'],
  ['org�nico', 'orgánico'],
  ['Org�nica', 'Orgánica'],
  ['org�nica', 'orgánica'],
  ['Cl�sico', 'Clásico'],
  ['cl�sico', 'clásico'],
  ['Caf�', 'Café'],
  ['caf�', 'café'],
  ['D�til', 'Dátil'],
  ['d�til', 'dátil'],
  ['Pat�', 'Paté'],
  ['pat�', 'paté'],
  ['Alm�bar', 'Almíbar'],
  ['alm�bar', 'almíbar'],
  ['Aj�', 'Ají'],
  ['aj�', 'ají'],
]

export function fixEncoding(text: string): string {
  let result = text
  for (const [bad, good] of ENCODING_FIXES) {
    if (result.includes(bad)) {
      result = result.split(bad).join(good)
    }
  }
  return result.trim().replace(/\s+/g, ' ')
}

// ====== normalizeCategoria ======

const CATEGORIA_MAP: Record<string, string> = {
  'frutas disecadas': 'Frutas Disecadas',
  mermelada: 'Mermeladas',
  'mix frutos secos': 'Mix de Frutos secos',
}

export function normalizeCategoria(text: string): string {
  const trimmed = text.trim().replace(/\s+/g, ' ')
  const key = trimmed.toLowerCase()
  return CATEGORIA_MAP[key] ?? trimmed
}

// ====== extractPresentacion ======

const PRESENTACION_REGEX =
  /\s*(?:x\s+)?(\d+(?:[.,]\d+)?\s*(?:kg|g|ml|l|cc|u|und|unidad|unidades)s?)\s*$/i

export function extractPresentacion(nombre: string): {
  nombre: string
  presentacion: string
} {
  const cleanedInput = nombre.trim()
  const match = cleanedInput.match(PRESENTACION_REGEX)
  if (!match || match.index === undefined) {
    return { nombre: cleanedInput, presentacion: '1 unidad' }
  }
  return {
    nombre: cleanedInput.slice(0, match.index).trim(),
    presentacion: match[1].trim().toLowerCase().replace(/\s+/g, ' '),
  }
}

// ====== normalizeRow ======

export function normalizeRow(raw: RawCatalogRow): NormalizedCatalogRow {
  const nombreFijo = fixEncoding(raw.nombre)
  const { nombre, presentacion } = extractPresentacion(nombreFijo)
  const categoria = normalizeCategoria(raw.categoria ?? 'Sin categoría')
  const descripcion = raw.descripcion?.trim() ? fixEncoding(raw.descripcion.trim()) : null
  const tienePrecio = raw.precio !== null && raw.precio > 0

  return {
    nombre_publico: nombre,
    categoria,
    descripcion,
    presentacion,
    precio_venta: tienePrecio ? raw.precio : null,
    precio_modo: 'markup_sobre_costo',
    markup_pct: 20,
    imagen: raw.imagen?.trim() || null,
    activo: tienePrecio,
  }
}
