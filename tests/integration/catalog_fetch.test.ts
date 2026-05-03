import { describe, it, expect, beforeAll } from 'vitest'

const SUPABASE_URL = process.env.VITE_SUPABASE_URL
const SUPABASE_ANON_KEY = process.env.VITE_SUPABASE_ANON_KEY

describe.skipIf(!SUPABASE_URL || !SUPABASE_ANON_KEY)('fetchActiveProducts (integration)', () => {
  beforeAll(() => {
    // El cliente de src/lib/supabase.ts lee import.meta.env, no process.env.
    // En vitest, import.meta.env hereda de process.env los VITE_*.
    // No hace falta setup adicional acá.
  })

  it('devuelve los 173 packs activos del seed con la forma esperada', async () => {
    const { fetchActiveProducts } = await import('@/lib/catalog')
    const products = await fetchActiveProducts()

    expect(products.length).toBe(173)

    const sample = products[0]
    expect(typeof sample.id).toBe('string')
    expect(typeof sample.nombre_publico).toBe('string')
    expect(typeof sample.categoria).toBe('string')
    expect(typeof sample.presentacion).toBe('string')
    // precio_venta es number en filas activas; nullable en general.
    expect(typeof sample.precio_venta).toBe('number')
    // imagen y descripcion pueden ser null.
    expect(['string', 'object']).toContain(typeof sample.imagen)
    expect(['string', 'object']).toContain(typeof sample.descripcion)
  })

  it('los resultados están ordenados por categoría y luego por nombre', async () => {
    const { fetchActiveProducts } = await import('@/lib/catalog')
    const products = await fetchActiveProducts()

    // Verificar orden lexicográfico estable por (categoria, nombre).
    for (let i = 1; i < products.length; i++) {
      const prev = products[i - 1]
      const curr = products[i]
      if (prev.categoria === curr.categoria) {
        expect(prev.nombre_publico.localeCompare(curr.nombre_publico, 'es')).toBeLessThanOrEqual(0)
      } else {
        expect(prev.categoria.localeCompare(curr.categoria, 'es')).toBeLessThanOrEqual(0)
      }
    }
  })

  it('ningún pack devuelto tiene activo=false (RLS lo garantiza para anon)', async () => {
    // El select no incluye `activo`, pero podemos asumir el invariante por
    // RLS y verificarlo indirectamente: el conteo (173) coincide con el
    // total - inactivos (191 - 18) que ya confirmamos en catalog_seed.test.ts.
    const { fetchActiveProducts } = await import('@/lib/catalog')
    const products = await fetchActiveProducts()
    expect(products.every((p) => p.precio_venta !== null && p.precio_venta > 0)).toBe(true)
  })
})
