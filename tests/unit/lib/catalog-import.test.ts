import { describe, it, expect } from 'vitest'
import {
  fixEncoding,
  normalizeCategoria,
  extractPresentacion,
  normalizeRow,
  type RawCatalogRow,
} from '@/lib/catalog-import'

describe('fixEncoding', () => {
  it('repara Caj� en mayúscula y minúscula', () => {
    expect(fixEncoding('Caj� W4 brasilero')).toBe('Cajú W4 brasilero')
    expect(fixEncoding('castañas de caj�')).toBe('castañas de cajú')
  })

  it('repara Casta�as → Castañas', () => {
    expect(fixEncoding('Casta�as de PARA')).toBe('Castañas de PARA')
  })

  it('repara Man� → Maní', () => {
    expect(fixEncoding('Man� tostado con sal')).toBe('Maní tostado con sal')
  })

  it('repara Az�car, S�samo, Ch�a, Ar�ndanos, Org�nico, D�tiles', () => {
    expect(fixEncoding('Az�car negra')).toBe('Azúcar negra')
    expect(fixEncoding('S�samo blanco')).toBe('Sésamo blanco')
    expect(fixEncoding('Ch�a premium')).toBe('Chía premium')
    expect(fixEncoding('Ar�ndanos')).toBe('Arándanos')
    expect(fixEncoding('Yerba Org�nica')).toBe('Yerba Orgánica')
    expect(fixEncoding('D�tiles Medjoul')).toBe('Dátiles Medjoul')
  })

  it('deja texto limpio igual y colapsa whitespace excesivo', () => {
    expect(fixEncoding('Nuez Mariposa Extra Light')).toBe('Nuez Mariposa Extra Light')
    expect(fixEncoding('  Nuez   Mariposa  ')).toBe('Nuez Mariposa')
  })

  it('si quedan caracteres irrecuperables (�) los preserva sin romper', () => {
    // Patrón no contemplado: deja el � para que el admin lo detecte.
    const out = fixEncoding('PalabraDesconocida�XYZ')
    expect(out).toContain('�')
  })
})

describe('normalizeCategoria', () => {
  it('canoniza "frutas Disecadas" (case fix) a "Frutas Disecadas"', () => {
    expect(normalizeCategoria('frutas Disecadas')).toBe('Frutas Disecadas')
    expect(normalizeCategoria('Frutas Disecadas')).toBe('Frutas Disecadas')
  })

  it('unifica "Mermelada" (singular) en "Mermeladas" (plural canónico)', () => {
    expect(normalizeCategoria('Mermelada')).toBe('Mermeladas')
    expect(normalizeCategoria('Mermeladas')).toBe('Mermeladas')
  })

  it('unifica "Mix Frutos secos " (sin "de" y trailing space) en "Mix de Frutos secos"', () => {
    expect(normalizeCategoria('Mix Frutos secos ')).toBe('Mix de Frutos secos')
    expect(normalizeCategoria('Mix de Frutos secos')).toBe('Mix de Frutos secos')
  })

  it('preserva categorías sin variante conocida (solo trim)', () => {
    expect(normalizeCategoria('Frutos Secos')).toBe('Frutos Secos')
    expect(normalizeCategoria('Yerbas')).toBe('Yerbas')
    expect(normalizeCategoria('  Confituras  ')).toBe('Confituras')
  })
})

describe('extractPresentacion', () => {
  it('extrae "1 kg" tras "x 1 Kg" y limpia el nombre', () => {
    expect(extractPresentacion('Nuez Mariposa Extra Light  x 1 Kg')).toEqual({
      nombre: 'Nuez Mariposa Extra Light',
      presentacion: '1 kg',
    })
  })

  it('acepta presentación sin "x" previa', () => {
    expect(extractPresentacion('Bananas disecadas 1kg')).toEqual({
      nombre: 'Bananas disecadas',
      presentacion: '1kg',
    })
  })

  it('extrae "5kg" cuando es la presentación', () => {
    expect(extractPresentacion('Higos negros x 5kg')).toEqual({
      nombre: 'Higos negros',
      presentacion: '5kg',
    })
  })

  it('default "1 unidad" si la presentación no es parseable trivialmente', () => {
    expect(extractPresentacion('VITAMINA E (30)')).toEqual({
      nombre: 'VITAMINA E (30)',
      presentacion: '1 unidad',
    })
    expect(extractPresentacion('Datiles Egipto Caja 1 kg OFERTA')).toEqual({
      nombre: 'Datiles Egipto Caja 1 kg OFERTA',
      presentacion: '1 unidad',
    })
  })
})

describe('normalizeRow', () => {
  const baseRaw: RawCatalogRow = {
    id: 1,
    nombre: 'Producto X',
    categoria: 'Frutos Secos',
    descripcion: null,
    precio: 100,
    imagen: 'https://img/x.jpg',
  }

  it('fija encoding del nombre y normaliza categoría', () => {
    const result = normalizeRow({
      ...baseRaw,
      nombre: 'Caj� W4',
      categoria: 'frutas Disecadas',
    })
    // El nombre se separa en nombre_publico + presentacion (sin matchear acá → "1 unidad")
    expect(result.nombre_publico).toBe('Cajú W4')
    expect(result.categoria).toBe('Frutas Disecadas')
    expect(result.presentacion).toBe('1 unidad')
  })

  it('extrae presentación cuando está en el nombre', () => {
    const result = normalizeRow({
      ...baseRaw,
      nombre: 'Nuez Mariposa Extra Light  x 1 Kg',
    })
    expect(result.nombre_publico).toBe('Nuez Mariposa Extra Light')
    expect(result.presentacion).toBe('1 kg')
  })

  it('aplica defaults de SPEC §9.1: precio_modo=markup_sobre_costo, markup_pct=20', () => {
    const result = normalizeRow(baseRaw)
    expect(result.precio_modo).toBe('markup_sobre_costo')
    expect(result.markup_pct).toBe(20)
  })

  it('marca activo=false cuando precio es null o 0', () => {
    expect(normalizeRow({ ...baseRaw, precio: null }).activo).toBe(false)
    expect(normalizeRow({ ...baseRaw, precio: 0 }).activo).toBe(false)
    expect(normalizeRow({ ...baseRaw, precio: 100 }).activo).toBe(true)
  })

  it('precio_venta=null cuando no hay precio (nullable en SPEC)', () => {
    expect(normalizeRow({ ...baseRaw, precio: null }).precio_venta).toBeNull()
  })

  it('preserva imagen y descripcion como vienen', () => {
    const result = normalizeRow({
      ...baseRaw,
      descripcion: 'Una descripción',
      imagen: 'https://example.com/img.jpg',
    })
    expect(result.descripcion).toBe('Una descripción')
    expect(result.imagen).toBe('https://example.com/img.jpg')
  })
})
