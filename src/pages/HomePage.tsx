import { useEffect, useMemo, useState } from 'react'
import { fetchActiveProducts, filterProducts, listCategorias, type Product } from '@/lib/catalog'
import { ProductCard } from '@/components/ProductCard'

type LoadState =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; products: Product[] }

export function HomePage() {
  const [state, setState] = useState<LoadState>({ status: 'loading' })
  const [search, setSearch] = useState('')
  const [categoria, setCategoria] = useState('')

  useEffect(() => {
    let cancelled = false
    fetchActiveProducts()
      .then((products) => {
        if (!cancelled) setState({ status: 'ready', products })
      })
      .catch((err: unknown) => {
        if (cancelled) return
        const message = err instanceof Error ? err.message : 'Error desconocido'
        setState({ status: 'error', message })
      })
    return () => {
      cancelled = true
    }
  }, [])

  const allProducts = useMemo(() => (state.status === 'ready' ? state.products : []), [state])
  const categorias = useMemo(() => listCategorias(allProducts), [allProducts])
  const filtered = useMemo(
    () => filterProducts(allProducts, { search, categoria: categoria || undefined }),
    [allProducts, search, categoria],
  )

  return (
    <main className="min-h-screen bg-stone-50 text-stone-900">
      <header className="border-b border-stone-200 bg-white">
        <div className="mx-auto max-w-6xl px-4 py-6 sm:px-6">
          <h1 className="text-3xl font-bold text-[#2E7D32]">M&amp;M Vida Saludable</h1>
          <p className="mt-1 text-sm text-stone-600">Catálogo de productos naturales</p>
        </div>
      </header>

      <section className="mx-auto max-w-6xl px-4 py-6 sm:px-6">
        <div className="mb-6 flex flex-col gap-3 sm:flex-row">
          <label className="flex-1">
            <span className="sr-only">Buscar producto</span>
            <input
              type="search"
              placeholder="Buscar producto…"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full rounded border border-stone-300 px-3 py-2 text-stone-900 focus:border-[#2E7D32] focus:outline-none"
            />
          </label>
          <label className="sm:w-64">
            <span className="sr-only">Filtrar por categoría</span>
            <select
              value={categoria}
              onChange={(e) => setCategoria(e.target.value)}
              className="w-full rounded border border-stone-300 px-3 py-2 text-stone-900 focus:border-[#2E7D32] focus:outline-none"
            >
              <option value="">Todas las categorías</option>
              {categorias.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
          </label>
        </div>

        {state.status === 'loading' && (
          <p className="text-stone-500" role="status">
            Cargando catálogo…
          </p>
        )}

        {state.status === 'error' && (
          <p className="text-red-600" role="alert">
            No pudimos cargar el catálogo. Intentalo más tarde. ({state.message})
          </p>
        )}

        {state.status === 'ready' && filtered.length === 0 && (
          <p className="text-stone-500" role="status">
            No hay productos que coincidan con los filtros.
          </p>
        )}

        {state.status === 'ready' && filtered.length > 0 && (
          <div
            className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4"
            data-testid="catalog-grid"
          >
            {filtered.map((p) => (
              <ProductCard key={p.id} product={p} />
            ))}
          </div>
        )}

        <p className="mt-8 text-center text-xs text-stone-400">
          {state.status === 'ready' &&
            `${filtered.length} de ${allProducts.length} productos visibles`}
        </p>
      </section>
    </main>
  )
}
