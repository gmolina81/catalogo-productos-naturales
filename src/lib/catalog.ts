import { getSupabase } from './supabase'

/**
 * Forma del pack tal como lo consume el catálogo público.
 * No incluye campos sólo-admin (markup_pct, precio_modo, id_producto_proveedor).
 */
export type Product = {
  id: string
  nombre_publico: string
  categoria: string
  descripcion: string | null
  presentacion: string
  precio_venta: number | null
  imagen: string | null
}

const SELECT_FIELDS =
  'id, nombre_publico, categoria, descripcion, presentacion, precio_venta, imagen'

/**
 * Trae todos los packs activos, ordenados por categoría y nombre.
 * RLS deja a `anon` ver solo `activo = true`, así que no hay que filtrar
 * acá explícitamente — la policy lo garantiza.
 */
export async function fetchActiveProducts(): Promise<Product[]> {
  const supabase = getSupabase()
  const { data, error } = await supabase
    .from('productos_negocio')
    .select(SELECT_FIELDS)
    .order('categoria', { ascending: true })
    .order('nombre_publico', { ascending: true })

  if (error) {
    throw new Error(`fetchActiveProducts: ${error.message}`)
  }
  return (data ?? []) as Product[]
}

export type ProductFilter = {
  search?: string
  categoria?: string
}

/**
 * Filtrado client-side. Se filtra una lista chica (~190 items) ya cargada en memoria.
 * - `search`: matchea en nombre_publico (case-insensitive, trim).
 * - `categoria`: match exacto.
 */
export function filterProducts(products: Product[], filter: ProductFilter): Product[] {
  const search = filter.search?.trim().toLowerCase() ?? ''
  const { categoria } = filter

  return products.filter((p) => {
    if (categoria && p.categoria !== categoria) return false
    if (search && !p.nombre_publico.toLowerCase().includes(search)) return false
    return true
  })
}

/**
 * Lista única y ordenada de categorías presentes en una colección de packs.
 */
export function listCategorias(products: Product[]): string[] {
  const set = new Set(products.map((p) => p.categoria))
  return [...set].sort((a, b) => a.localeCompare(b, 'es'))
}
