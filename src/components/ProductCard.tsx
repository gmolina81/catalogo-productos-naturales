import { useState } from 'react'
import type { Product } from '@/lib/catalog'

type Props = {
  product: Product
}

const PESO_FORMAT = new Intl.NumberFormat('es-AR', {
  style: 'currency',
  currency: 'ARS',
  maximumFractionDigits: 0,
})

export function ProductCard({ product }: Props) {
  const [imgError, setImgError] = useState(false)
  const showImage = product.imagen && !imgError

  return (
    <article className="overflow-hidden rounded-lg bg-white shadow transition-shadow hover:shadow-md">
      <div className="aspect-square w-full bg-stone-100">
        {showImage ? (
          <img
            src={product.imagen!}
            alt={product.nombre_publico}
            loading="lazy"
            onError={() => setImgError(true)}
            className="h-full w-full object-cover"
          />
        ) : (
          <div className="flex h-full w-full items-center justify-center text-sm text-stone-400">
            sin imagen
          </div>
        )}
      </div>

      <div className="space-y-2 p-4">
        <span className="inline-block rounded bg-green-50 px-2 py-0.5 text-xs font-medium text-[#2E7D32]">
          {product.categoria}
        </span>
        <h3 className="text-base leading-snug font-semibold text-stone-900">
          {product.nombre_publico}
        </h3>
        <p className="text-xs text-stone-500">{product.presentacion}</p>
        <p className="text-xl font-bold text-[#2E7D32]">
          {product.precio_venta !== null ? (
            PESO_FORMAT.format(product.precio_venta)
          ) : (
            <span className="text-base font-medium text-stone-500">Consultar precio</span>
          )}
        </p>
      </div>
    </article>
  )
}
