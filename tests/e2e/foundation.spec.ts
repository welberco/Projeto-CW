import { expect, test } from '@playwright/test'

test('renders the V2 technical shell at the root route', async ({ page }) => {
  await page.goto('/')

  await expect(
    page.getByRole('heading', { name: 'Foundation frontend executável' }),
  ).toBeVisible()
  await expect(page.getByText('CW ERP V2')).toBeVisible()
})

test('keeps the tenant route opaque across navigation and refresh', async ({
  page,
}) => {
  await page.goto('/')
  await page.goto('/e/opaque-ref_123')

  await expect(
    page.getByRole('heading', { name: 'Espaço de empreendimento' }),
  ).toBeVisible()
  await expect(page.getByText('opaque-ref_123')).toBeVisible()

  await page.reload()
  await expect(
    page.getByRole('heading', { name: 'Espaço de empreendimento' }),
  ).toBeVisible()

  await page.goBack()
  await expect(
    page.getByRole('heading', { name: 'Foundation frontend executável' }),
  ).toBeVisible()

  await page.goForward()
  await expect(page.getByText('opaque-ref_123')).toBeVisible()
})

test('renders the platform boundary', async ({ page }) => {
  await page.goto('/plataforma')

  await expect(
    page.getByRole('heading', { name: 'Operações de plataforma' }),
  ).toBeVisible()
  await expect(
    page.getByText(/Nenhuma função de Administrador Global/),
  ).toBeVisible()
})

test('renders a safe not-found state for an unknown deep link', async ({
  page,
}) => {
  await page.goto('/rota-inexistente')

  await expect(
    page.getByRole('heading', { name: 'Página não encontrada' }),
  ).toBeVisible()
})
