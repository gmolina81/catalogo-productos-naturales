import { describe, it, expect, beforeAll } from 'vitest'
import { createClient, type SupabaseClient } from '@supabase/supabase-js'

/**
 * Tests del seed del catálogo (Fase 1.4).
 *
 * Asume que `supabase db reset` ya corrió y `supabase/seed-catalog.sql`
 * fue generado con `npm run seed:generate` desde el Excel del negocio.
 *
 * Verifica conteos y forma de los datos cargados — no testea cada fila,
 * solo los invariantes que importan para el resto de la app.
 */

const SUPABASE_URL = process.env.VITE_SUPABASE_URL
const SUPABASE_ANON_KEY = process.env.VITE_SUPABASE_ANON_KEY

const TEST_EMAIL = 'admin@test.local'
const TEST_PASSWORD = 'E2eAdminPass2026!'

describe.skipIf(!SUPABASE_URL || !SUPABASE_ANON_KEY)('catalog seed', () => {
  let supabaseAnon: SupabaseClient
  let supabaseAdmin: SupabaseClient

  beforeAll(async () => {
    supabaseAnon = createClient(SUPABASE_URL!, SUPABASE_ANON_KEY!, {
      auth: { persistSession: false },
    })
    // Cliente autenticado como admin para ver TODOS los packs (incluyendo activo=false).
    supabaseAdmin = createClient(SUPABASE_URL!, SUPABASE_ANON_KEY!, {
      auth: { persistSession: false },
    })
    const { error } = await supabaseAdmin.auth.signInWithPassword({
      email: TEST_EMAIL,
      password: TEST_PASSWORD,
    })
    if (error) throw error
  })

  it('cargó 191 productos en productos_negocio (todos los del Excel sin filas vacías)', async () => {
    const { count, error } = await supabaseAdmin
      .from('productos_negocio')
      .select('*', { count: 'exact', head: true })
    expect(error).toBeNull()
    expect(count).toBe(191)
  })

  it('todos los packs cargados tienen id_producto_proveedor = NULL (Fase 1; admin asocia en Fase 2)', async () => {
    const { count, error } = await supabaseAdmin
      .from('productos_negocio')
      .select('*', { count: 'exact', head: true })
      .not('id_producto_proveedor', 'is', null)
    expect(error).toBeNull()
    expect(count).toBe(0)
  })

  it('todos los packs cargados tienen precio_modo=markup_sobre_costo y markup_pct=20 (decisión §9.1)', async () => {
    const { count: bad, error } = await supabaseAdmin
      .from('productos_negocio')
      .select('*', { count: 'exact', head: true })
      .or('precio_modo.neq.markup_sobre_costo,markup_pct.neq.20')
    expect(error).toBeNull()
    expect(bad).toBe(0)
  })

  it('los packs sin precio en el Excel están marcados activo=false', async () => {
    const { data: inactivos, error: e1 } = await supabaseAdmin
      .from('productos_negocio')
      .select('id, precio_venta, activo')
      .eq('activo', false)
    expect(e1).toBeNull()
    expect(inactivos!.length).toBe(18)
    // Y todos ellos tienen precio_venta = NULL (no se cargó el precio).
    expect(inactivos!.every((p) => p.precio_venta === null)).toBe(true)
  })

  it('anon SELECT solo ve packs activos (RLS pública)', async () => {
    const { count, error } = await supabaseAnon
      .from('productos_negocio')
      .select('*', { count: 'exact', head: true })
    expect(error).toBeNull()
    // 191 - 18 inactivos = 173 visibles para anon.
    expect(count).toBe(173)
  })

  it('cada pack tiene su mapeo_pack_bulto placeholder (1:1)', async () => {
    const { count, error } = await supabaseAdmin
      .from('mapeo_pack_bulto')
      .select('*', { count: 'exact', head: true })
    expect(error).toBeNull()
    expect(count).toBe(191)
  })

  it('los placeholders de mapeo_pack_bulto tienen packs_por_bulto=1 y merma_pct=0', async () => {
    const { count: bad, error } = await supabaseAdmin
      .from('mapeo_pack_bulto')
      .select('*', { count: 'exact', head: true })
      .or('packs_por_bulto.neq.1,merma_pct.neq.0')
    expect(error).toBeNull()
    expect(bad).toBe(0)
  })

  it('los nombres con encoding fixed se cargaron correctamente (no quedan U+FFFD)', async () => {
    const { count, error } = await supabaseAdmin
      .from('productos_negocio')
      .select('*', { count: 'exact', head: true })
      .like('nombre_publico', '%�%')
    expect(error).toBeNull()
    expect(count).toBe(0)
  })
})
