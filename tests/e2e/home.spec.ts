import { test, expect } from '@playwright/test'

test('home muestra el header del catálogo', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { name: /M&M Vida Saludable/i })).toBeVisible()
})

test('sin errores JS al cargar', async ({ page }) => {
  const errors: string[] = []
  page.on('pageerror', (err) => errors.push(err.message))

  await page.goto('/')
  // No usamos networkidle: la grilla pide ~170 imágenes a CDNs externos y
  // algunas tardan o fallan, manteniendo la red ocupada. Esperamos a que
  // la grilla del catálogo esté visible y damos un margen para que los
  // hooks de React terminen.
  await expect(page.getByTestId('catalog-grid')).toBeVisible()
  await page.waitForTimeout(200)

  expect(errors).toEqual([])
})
