import { useNavigate } from 'react-router-dom'
import { logoutAdmin } from '@/lib/auth'
import { useSession } from '@/hooks/useSession'

export function AdminHomePage() {
  const { session } = useSession()
  const navigate = useNavigate()

  async function handleLogout() {
    await logoutAdmin()
    navigate('/admin/login', { replace: true })
  }

  return (
    <main className="min-h-screen bg-stone-50 text-stone-900">
      <header className="flex items-center justify-between border-b border-stone-200 bg-white px-6 py-4">
        <h1 className="text-xl font-bold text-[#2E7D32]">Panel admin</h1>
        <div className="flex items-center gap-4 text-sm">
          {session?.user?.email && <span className="text-stone-600">{session.user.email}</span>}
          <button
            type="button"
            onClick={handleLogout}
            className="rounded border border-stone-300 px-3 py-1 text-stone-700 hover:bg-stone-100"
          >
            Cerrar sesión
          </button>
        </div>
      </header>

      <div className="mx-auto max-w-3xl px-6 py-12">
        <p className="text-stone-600">
          Panel en construcción. Las vistas de catálogo, sincronización, pedidos y orden de compra
          se implementan en Fase 2 y 3.
        </p>
      </div>
    </main>
  )
}
