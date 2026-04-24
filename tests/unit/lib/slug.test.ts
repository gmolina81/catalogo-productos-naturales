import { describe, it, expect } from 'vitest'
import { slugify, codigoExterno } from '@/lib/slug'

describe('slugify', () => {
  it('pasa a minúsculas', () => {
    expect(slugify('HOLA')).toBe('hola')
  })

  it('quita acentos y eñes', () => {
    expect(slugify('Castañas de Pará')).toBe('castanas-de-para')
  })

  it('colapsa espacios y puntuación en un solo guion', () => {
    expect(slugify('  Nuez   Mariposa (extra, light)  ')).toBe('nuez-mariposa-extra-light')
  })

  it('elimina guiones al principio y al final', () => {
    expect(slugify('--foo--')).toBe('foo')
  })
})

describe('codigoExterno', () => {
  it('combina nombre y presentación con pipe', () => {
    expect(codigoExterno('Nuez Mariposa Extra Light 2026', '10KG')).toBe(
      'nuez-mariposa-extra-light-2026|10kg',
    )
  })

  it('dos presentaciones del mismo producto generan códigos distintos', () => {
    const a = codigoExterno('Almendra Non Pareil 27/30', '5KG')
    const b = codigoExterno('Almendra Non Pareil 27/30', '1KG')
    expect(a).not.toBe(b)
    expect(a).toBe('almendra-non-pareil-27-30|5kg')
    expect(b).toBe('almendra-non-pareil-27-30|1kg')
  })
})
