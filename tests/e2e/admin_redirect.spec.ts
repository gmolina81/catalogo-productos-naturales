import { test, expect } from '@playwright/test'

test.describe('admin routes', () => {
  test('usuario no autenticado en /admin es redirigido a /admin/login', async ({ page }) => {
    await page.goto('/admin')
    await expect(page).toHaveURL(/\/admin\/login$/)
    await expect(page.getByRole('heading', { name: /ingresar al panel/i })).toBeVisible()
  })

  test('/admin/login muestra el formulario', async ({ page }) => {
    await page.goto('/admin/login')
    await expect(page.getByLabel(/email/i)).toBeVisible()
    await expect(page.getByLabel(/contraseña/i)).toBeVisible()
    await expect(page.getByRole('button', { name: /ingresar/i })).toBeVisible()
  })

  test('login con credenciales inválidas muestra mensaje genérico', async ({ page }) => {
    await page.goto('/admin/login')
    await page.getByLabel(/email/i).fill('nadie@example.com')
    await page.getByLabel(/contraseña/i).fill('whatever1234!')
    await page.getByRole('button', { name: /ingresar/i }).click()

    await expect(page.getByRole('alert')).toContainText(/credenciales inválidas/i)
    // Sigue en la página de login.
    await expect(page).toHaveURL(/\/admin\/login$/)
  })
})
