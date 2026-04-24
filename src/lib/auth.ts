import type { Session } from '@supabase/supabase-js'
import { getSupabase } from './supabase'

/**
 * Intenta loguear al admin. Devuelve la sesión si fue exitoso, o null si
 * las credenciales son inválidas. Nunca lanza por credenciales — el caller
 * muestra un mensaje genérico (SPEC §5.3.1: "Credenciales inválidas" sin
 * revelar si el email existe).
 *
 * Al éxito, registra la acción `login` en admin_audit_log vía RPC.
 * En caso de fallo, NO logueamos del lado del cliente: anon no tiene EXECUTE
 * sobre log_admin_action (ver §6.4), y Supabase Auth ya loguea el intento
 * fallido en auth.audit_log_entries.
 */
export async function loginAdmin(email: string, password: string): Promise<Session | null> {
  const supabase = getSupabase()
  const { data, error } = await supabase.auth.signInWithPassword({ email, password })

  if (error || !data.session) {
    return null
  }

  // Audit — si falla el RPC, el login igual fue exitoso; logueamos el error en consola
  // pero no bloqueamos al usuario.
  const { error: auditError } = await supabase.rpc('log_admin_action', {
    p_accion: 'login',
    p_detalle: { email },
    p_user_agent: typeof navigator !== 'undefined' ? navigator.userAgent : null,
  })
  if (auditError) {
    console.warn('log_admin_action (login) failed:', auditError)
  }

  return data.session
}

/**
 * Cierra la sesión. Registra `logout` en el audit ANTES de `signOut` (para que
 * el JWT todavía sea válido al llamar al RPC).
 */
export async function logoutAdmin(): Promise<void> {
  const supabase = getSupabase()

  const { error: auditError } = await supabase.rpc('log_admin_action', {
    p_accion: 'logout',
    p_user_agent: typeof navigator !== 'undefined' ? navigator.userAgent : null,
  })
  if (auditError) {
    console.warn('log_admin_action (logout) failed:', auditError)
  }

  await supabase.auth.signOut()
}

export async function getCurrentSession(): Promise<Session | null> {
  const supabase = getSupabase()
  const { data } = await supabase.auth.getSession()
  return data.session
}
