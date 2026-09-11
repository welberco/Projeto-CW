import { expect, test } from '@playwright/test'

test('redirects the unauthenticated root route to login', async ({ page }) => {
  await page.goto('/')

  await expect(page.getByRole('heading', { name: 'Entrar' })).toBeVisible()
  await expect(page).toHaveURL(/\/login$/)
})

test('keeps an unauthenticated tenant deep link fail-closed across refresh', async ({
  page,
}) => {
  const tenantRef = '34000000-0000-4000-8000-000000000001'
  await page.goto('/login')
  await page.goto(`/e/${tenantRef}/dashboard`)

  await expect(
    page.getByRole('heading', { name: 'Autenticação necessária' }),
  ).toBeVisible()
  await expect(page.getByText(tenantRef)).not.toBeVisible()
  await expect(page.getByRole('heading', { name: 'Visão Geral' })).not.toBeVisible()

  await page.reload()
  await expect(
    page.getByRole('heading', { name: 'Autenticação necessária' }),
  ).toBeVisible()

  await page.goBack()
  await expect(page.getByRole('heading', { name: 'Entrar' })).toBeVisible()

  await page.goForward()
  await expect(
    page.getByRole('heading', { name: 'Autenticação necessária' }),
  ).toBeVisible()
})

test('protects the platform namespace', async ({ page }) => {
  await page.goto('/plataforma')

  await expect(
    page.getByRole('heading', { name: 'Autenticação necessária' }),
  ).toBeVisible()
  await expect(page.getByText(/bypass/)).not.toBeVisible()
})

test('renders a safe not-found state for an unknown deep link', async ({
  page,
}) => {
  await page.goto('/rota-inexistente')

  await expect(
    page.getByRole('heading', { name: 'Página não encontrada' }),
  ).toBeVisible()
})

test('renders the login route without signup', async ({ page }) => {
  await page.goto('/login')

  await expect(page.getByRole('heading', { name: 'Entrar' })).toBeVisible()
  await expect(page.getByText(/Não há cadastro público/)).toBeVisible()
})

test('keeps an invalid invitation in a safe state', async ({ page }) => {
  await page.goto('/convite')

  await expect(
    page.getByRole('heading', { name: 'Convite indisponível' }),
  ).toBeVisible()
})
