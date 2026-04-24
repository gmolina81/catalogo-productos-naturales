import { useEffect, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { getSupabase } from '@/lib/supabase'

type SessionState = {
  session: Session | null
  /** true hasta que sabemos si hay sesión o no (primer getSession termina). */
  loading: boolean
}

/**
 * Hook que escucha el estado de auth. Carga inicial con `getSession()` y
 * actualiza con `onAuthStateChange` (login / logout / refresh de token).
 */
export function useSession(): SessionState {
  const [state, setState] = useState<SessionState>({ session: null, loading: true })

  useEffect(() => {
    const supabase = getSupabase()
    let cancelled = false

    supabase.auth.getSession().then(({ data }) => {
      if (!cancelled) {
        setState({ session: data.session, loading: false })
      }
    })

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      if (!cancelled) {
        setState({ session, loading: false })
      }
    })

    return () => {
      cancelled = true
      subscription.unsubscribe()
    }
  }, [])

  return state
}
