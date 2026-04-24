import { describe, it, expect, beforeAll } from 'vitest'
import { createClient, type SupabaseClient } from '@supabase/supabase-js'

/**
 * Tests de integración contra una DB local levantada con `supabase start`.
 * En CI, el workflow hace `supabase start` y exporta las keys a process.env
 * antes de correr este suite.
 *
 * NO usamos el cliente de `src/lib/supabase.ts` porque aquel lee `import.meta.env`
 * y estos tests viven en el proyecto de integración con entorno node; más directo
 * instanciar el cliente acá con process.env.
 */

const SUPABASE_URL = process.env.VITE_SUPABASE_URL
const SUPABASE_ANON_KEY = process.env.VITE_SUPABASE_ANON_KEY

describe.skipIf(!SUPABASE_URL || !SUPABASE_ANON_KEY)('supabase integration', () => {
  let supabase: SupabaseClient

  beforeAll(() => {
    supabase = createClient(SUPABASE_URL!, SUPABASE_ANON_KEY!, {
      auth: { persistSession: false },
    })
  })

  it('anon puede SELECT productos_negocio activos (RLS pública)', async () => {
    const { data, error } = await supabase
      .from('productos_negocio')
      .select('id')
      .eq('activo', true)
      .limit(5)

    expect(error).toBeNull()
    expect(Array.isArray(data)).toBe(true)
  })

  it('anon NO puede SELECT productos_proveedor (solo admin)', async () => {
    const { data, error } = await supabase.from('productos_proveedor').select('id').limit(1)

    // RLS filtra: el SELECT no da error, pero devuelve 0 filas para anon.
    expect(error).toBeNull()
    expect(data).toEqual([])
  })

  it('anon NO puede INSERT directo en clientes (debe usar upsert_cliente RPC)', async () => {
    const { error } = await supabase
      .from('clientes')
      .insert({ nombre: 'Hack', telefono: '0000', email: 'hack@test.com' })

    expect(error).toBeTruthy()
    // 42501 en PostgreSQL se mapea en PostgREST a distintos formatos, pero
    // siempre lleva el mensaje de violation de RLS.
    expect(error?.message.toLowerCase()).toContain('row-level security')
  })

  it('upsert_cliente rechaza email inválido con código 22023', async () => {
    const { error } = await supabase.rpc('upsert_cliente', {
      p_email: 'no-es-email',
      p_nombre: 'Test',
      p_telefono: '1100000000',
    })

    expect(error).toBeTruthy()
    expect(error?.code).toBe('22023')
  })

  it('upsert_cliente crea un cliente con email válido', async () => {
    const email = `integ-${Date.now()}@test.com`
    const { data, error } = await supabase.rpc('upsert_cliente', {
      p_email: email,
      p_nombre: 'Cliente Integ',
      p_telefono: '1100000000',
    })

    expect(error).toBeNull()
    expect(typeof data).toBe('string') // retorna uuid
  })
})
