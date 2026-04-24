/**
 * Genera un slug minúscula, sin acentos, con guiones — el formato que usa
 * `productos_proveedor.codigo_externo` del SPEC v1.4 §4.1 y §5.3.3.1.
 */
export function slugify(input: string): string {
  return input
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
}

/**
 * Clave natural sintética para `productos_proveedor`: slug(nombre) + '|' + slug(presentacion).
 * Ej. codigoExterno("Nuez Mariposa Extra Light 2026", "10KG") === "nuez-mariposa-extra-light-2026|10kg"
 */
export function codigoExterno(nombreBase: string, presentacion: string): string {
  return `${slugify(nombreBase)}|${slugify(presentacion)}`
}
