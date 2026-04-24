import { useState, type FormEvent } from 'react'
import { Navigate, useLocation, useNavigate } from 'react-router-dom'
import { loginAdmin } from '@/lib/auth'
import { useSession } from '@/hooks/useSession'

type LocationState = { from?: { pathname?: string } } | null

export function LoginPage() {
  const { session, loading } = useSession()
  const navigate = useNavigate()
  const location = useLocation()

  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [errorMsg, setErrorMsg] = useState<string | null>(null)

  // Si ya estamos logueados, redirigir a /admin (o de donde veníamos).
  if (!loading && session) {
    const from = (location.state as LocationState)?.from?.pathname ?? '/admin'
    return <Navigate to={from} replace />
  }

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setErrorMsg(null)
    setSubmitting(true)

    let result = null
    try {
      result = await loginAdmin(email, password)
    } catch (err) {
      // Errores de red / excepciones inesperadas también deben dejar el UI
      // utilizable. Log en consola para debug, mensaje genérico al usuario.
      console.warn('loginAdmin threw:', err)
    }

    setSubmitting(false)

    if (!result) {
      // Mensaje genérico: SPEC §5.3.1 — no revelar si el email existe.
      setErrorMsg('Credenciales inválidas')
      return
    }

    const from = (location.state as LocationState)?.from?.pathname ?? '/admin'
    navigate(from, { replace: true })
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-stone-50 px-4">
      <form
        onSubmit={handleSubmit}
        className="w-full max-w-sm space-y-4 rounded-lg bg-white p-8 shadow"
        aria-labelledby="login-title"
      >
        <h1 id="login-title" className="text-2xl font-bold text-[#2E7D32]">
          Ingresar al panel
        </h1>

        <div>
          <label htmlFor="email" className="block text-sm font-medium text-stone-700">
            Email
          </label>
          <input
            id="email"
            type="email"
            required
            autoComplete="username"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="mt-1 block w-full rounded border border-stone-300 px-3 py-2 text-stone-900 focus:border-[#2E7D32] focus:outline-none"
          />
        </div>

        <div>
          <label htmlFor="password" className="block text-sm font-medium text-stone-700">
            Contraseña
          </label>
          <input
            id="password"
            type="password"
            required
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="mt-1 block w-full rounded border border-stone-300 px-3 py-2 text-stone-900 focus:border-[#2E7D32] focus:outline-none"
          />
        </div>

        {errorMsg && (
          <p role="alert" className="text-sm text-red-600">
            {errorMsg}
          </p>
        )}

        <button
          type="submit"
          disabled={submitting}
          className="w-full rounded bg-[#2E7D32] px-4 py-2 font-medium text-white hover:bg-[#256628] disabled:opacity-50"
        >
          {submitting ? 'Ingresando…' : 'Ingresar'}
        </button>
      </form>
    </main>
  )
}
