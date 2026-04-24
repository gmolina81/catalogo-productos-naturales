import type { ReactNode } from 'react'
import { Navigate, useLocation } from 'react-router-dom'
import { useSession } from '@/hooks/useSession'

type Props = {
  children: ReactNode
}

/**
 * Envuelve rutas `/admin/*`. Bloquea el render hasta saber si hay sesión
 * (estado `loading`) y redirige a `/admin/login` si no hay.
 *
 * SPEC §6.3: "La protección en el frontend es conveniencia de UX, no
 * seguridad". La seguridad real la da RLS en la DB.
 */
export function ProtectedRoute({ children }: Props) {
  const { session, loading } = useSession()
  const location = useLocation()

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-stone-50 text-stone-500">
        Cargando…
      </div>
    )
  }

  if (!session) {
    return <Navigate to="/admin/login" replace state={{ from: location }} />
  }

  return <>{children}</>
}
