import { describe, it, expect } from 'vitest'
import { filterProducts, type Product } from '@/lib/catalog'

const sample: Product[] = [
  {
    id: '1',
    nombre_publico: 'Nuez Mariposa',
    categoria: 'Frutos Secos',
    descripcion: null,
    presentacion: '1 kg',
    precio_venta: 1000,
    imagen: null,
  },
  {
    id: '2',
    nombre_publico: 'Almendra Non Pareil',
    categoria: 'Frutos Secos',
    descripcion: null,
    presentacion: '1 kg',
    precio_venta: 2000,
    imagen: null,
  },
  {
    id: '3',
    nombre_publico: 'Damasco Turco',
    categoria: 'Frutas Disecadas',
    descripcion: null,
    presentacion: '1 kg',
    precio_venta: 3000,
    imagen: null,
  },
]

describe('filterProducts', () => {
  it('sin filtros devuelve todo', () => {
    expect(filterProducts(sample, {}).map((p) => p.id)).toEqual(['1', '2', '3'])
  })

  it('filtra por categoría exacta', () => {
    expect(filterProducts(sample, { categoria: 'Frutos Secos' }).map((p) => p.id)).toEqual([
      '1',
      '2',
    ])
  })

  it('filtra por search en nombre (case-insensitive)', () => {
    expect(filterProducts(sample, { search: 'NUEZ' }).map((p) => p.id)).toEqual(['1'])
    expect(filterProducts(sample, { search: 'damasco' }).map((p) => p.id)).toEqual(['3'])
  })

  it('search ignora espacios al principio y al final', () => {
    expect(filterProducts(sample, { search: '  almendra  ' }).map((p) => p.id)).toEqual(['2'])
  })

  it('search vacío equivale a sin filtro', () => {
    expect(filterProducts(sample, { search: '' }).length).toBe(3)
    expect(filterProducts(sample, { search: '   ' }).length).toBe(3)
  })

  it('combina categoría y search', () => {
    expect(
      filterProducts(sample, { categoria: 'Frutos Secos', search: 'almendra' }).map((p) => p.id),
    ).toEqual(['2'])
    expect(filterProducts(sample, { categoria: 'Frutas Disecadas', search: 'nuez' }).length).toBe(0)
  })

  it('devuelve array vacío si nada matchea', () => {
    expect(filterProducts(sample, { search: 'xyz' })).toEqual([])
  })
})
