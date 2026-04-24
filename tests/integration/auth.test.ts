import { describe, it, expect, beforeEach } from 'vitest'
import { createClient, type SupabaseClient } from '@supabase/supabase-js'

/**
 * Tests de integración del flujo de auth contra Supabase local.
 * El seed en supabase/seed.sql crea un admin de prueba:
 *   email    = admin@test.local
 *   password = E2eAdminPass2026!
 */

const SUPABASE_URL = process.env.VITE_SUPABASE_URL
const SUPABASE_ANON_KEY = process.env.VITE_SUPABASE_ANON_KEY

const TEST_EMAIL = 'admin@test.local'
const TEST_PASSWORD = 'E2eAdminPass2026!'

describe.skipIf(!SUPABASE_URL || !SUPABASE_ANON_KEY)('auth integration', () => {
  let supabase: SupabaseClient

  beforeEach(() => {
    supabase = createClient(SUPABASE_URL!, SUPABASE_ANON_KEY!, {
      auth: { persistSession: false },
    })
  })

  it('login con credenciales válidas devuelve session + user', async () => {
    const { data, error } = await supabase.auth.signInWithPassword({
      email: TEST_EMAIL,
      password: TEST_PASSWORD,
    })

    expect(error).toBeNull()
    expect(data.session).toBeTruthy()
    expect(data.user?.email).toBe(TEST_EMAIL)
  })

  it('login con password incorrecta devuelve error y null session', async () => {
    const { data, error } = await supabase.auth.signInWithPassword({
      email: TEST_EMAIL,
      password: 'WrongPassword123!',
    })

    expect(error).toBeTruthy()
    expect(data.session).toBeNull()
    // GoTrue devuelve "Invalid login credentials" — mensaje genérico ya
    // (cumple SPEC §5.3.1 sin revelar si el email existe).
    expect(error?.message.toLowerCase()).toContain('invalid')
  })

  it('log_admin_action registra la acción login para el usuario autenticado', async () => {
    // 1. Login
    const { data: loginData, error: loginError } = await supabase.auth.signInWithPassword({
      email: TEST_EMAIL,
      password: TEST_PASSWORD,
    })
    expect(loginError).toBeNull()
    expect(loginData.session).toBeTruthy()

    // 2. Llamar al RPC como autenticado.
    const { error: rpcError } = await supabase.rpc('log_admin_action', {
      p_accion: 'login',
      p_detalle: { email: TEST_EMAIL },
      p_user_agent: 'vitest-integration',
    })
    expect(rpcError).toBeNull()

    // 3. Leer admin_audit_log (como authenticated tiene SELECT).
    const { data: logs, error: selectError } = await supabase
      .from('admin_audit_log')
      .select('accion, user_id, user_agent')
      .eq('user_agent', 'vitest-integration')

    expect(selectError).toBeNull()
    expect(logs).toBeTruthy()
    expect(logs!.length).toBeGreaterThanOrEqual(1)
    expect(logs![0].accion).toBe('login')
    expect(logs![0].user_id).toBe(loginData.user!.id)
  })

  it('signOut invalida la sesión', async () => {
    await supabase.auth.signInWithPassword({ email: TEST_EMAIL, password: TEST_PASSWORD })

    const before = await supabase.auth.getSession()
    expect(before.data.session).toBeTruthy()

    await supabase.auth.signOut()

    const after = await supabase.auth.getSession()
    expect(after.data.session).toBeNull()
  })
})
