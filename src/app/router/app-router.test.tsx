import { screen } from '@testing-library/react'
import { RouterProvider } from 'react-router-dom'
import { describe, expect, it } from 'vitest'
import { createAppMemoryRouter } from '@/app/router/app-router'
import { renderWithProviders } from '@/test/render-with-providers'

function renderRoute(path: string) {
  const router = createAppMemoryRouter([path])

  renderWithProviders(<RouterProvider router={router} />)
}

describe('app router', () => {
  it('renders the technical shell at the root route', async () => {
    renderRoute('/')

    expect(
      await screen.findByRole('heading', {
        name: 'Foundation frontend executável',
      }),
    ).toBeInTheDocument()
    expect(screen.getByText(/Correlação local, não autoritativa/)).toBeVisible()
  })

  it('treats tenantRef as an opaque route selector', async () => {
    renderRoute('/e/opaque-ref_123')

    expect(
      await screen.findByRole('heading', { name: 'Espaço de empreendimento' }),
    ).toBeInTheDocument()
    expect(screen.getByText('opaque-ref_123')).toBeVisible()
    expect(screen.getByText(/não cria tenant, membership ou autoridade/)).toBeVisible()
  })

  it('renders the platform boundary without platform functionality', async () => {
    renderRoute('/plataforma')

    expect(
      await screen.findByRole('heading', { name: 'Operações de plataforma' }),
    ).toBeInTheDocument()
    expect(screen.getByText(/Nenhuma função de Administrador Global/)).toBeVisible()
  })

  it('renders a safe not-found state for an unknown deep link', async () => {
    renderRoute('/rota-inexistente')

    expect(
      await screen.findByRole('heading', { name: 'Página não encontrada' }),
    ).toBeInTheDocument()
  })

  it('renders the login route without public signup', async () => {
    renderRoute('/login')

    expect(await screen.findByRole('heading', { name: 'Entrar' })).toBeVisible()
    expect(screen.getByText(/Não há cadastro público/)).toBeVisible()
  })

  it('requires a token for the invitation route', async () => {
    renderRoute('/convite')

    expect(
      await screen.findByRole('heading', { name: 'Convite indisponível' }),
    ).toBeVisible()
  })
})
