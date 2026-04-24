import { test, expect } from '@playwright/test'

test('home muestra el placeholder de scaffolding', async ({ page }) => {
  await page.goto('/')

  await expect(page.getByRole('heading', { name: /M&M Vida Saludable/i })).toBeVisible()
  await expect(page.getByText(/scaffolding inicial/i)).toBeVisible()
})

test('sin errores JS al cargar', async ({ page }) => {
  const errors: string[] = []
  page.on('pageerror', (err) => errors.push(err.message))

  await page.goto('/')
  await page.waitForLoadState('networkidle')

  expect(errors).toEqual([])
})
