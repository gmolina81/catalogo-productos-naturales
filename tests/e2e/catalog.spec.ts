import { test, expect } from '@playwright/test'

test.describe('catálogo público', () => {
  test('renderiza la grilla con productos del seed', async ({ page }) => {
    await page.goto('/')

    await expect(page.getByRole('heading', { name: /M&M Vida Saludable/i })).toBeVisible()

    // Espera a que la grilla aparezca (carga inicial fetch).
    const grid = page.getByTestId('catalog-grid')
    await expect(grid).toBeVisible()

    const cards = grid.locator('article')
    await expect(cards.first()).toBeVisible()

    // El seed activo tiene 173 packs visibles para anon.
    const count = await cards.count()
    expect(count).toBe(173)
  })

  test('search filtra la grilla en vivo', async ({ page }) => {
    await page.goto('/')
    await expect(page.getByTestId('catalog-grid')).toBeVisible()

    const searchInput = page.getByPlaceholder(/buscar producto/i)
    await searchInput.fill('nuez')

    const cards = page.getByTestId('catalog-grid').locator('article')
    // Hay productos con "nuez" en el nombre, pero menos que el total.
    await expect(cards.first()).toBeVisible()
    const count = await cards.count()
    expect(count).toBeGreaterThan(0)
    expect(count).toBeLessThan(173)
  })

  test('filtro por categoría reduce el listado', async ({ page }) => {
    await page.goto('/')
    await expect(page.getByTestId('catalog-grid')).toBeVisible()

    const select = page.locator('select').first()
    await select.selectOption({ label: 'Frutos Secos' })

    const cards = page.getByTestId('catalog-grid').locator('article')
    const count = await cards.count()
    expect(count).toBeGreaterThan(0)
    expect(count).toBeLessThan(173)
  })

  test('mensaje cuando ningún producto matchea', async ({ page }) => {
    await page.goto('/')
    await expect(page.getByTestId('catalog-grid')).toBeVisible()

    await page.getByPlaceholder(/buscar producto/i).fill('xyzpdq-no-existe')

    await expect(page.getByText(/no hay productos que coincidan/i)).toBeVisible()
  })
})
