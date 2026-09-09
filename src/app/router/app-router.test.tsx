import { QueryClient } from '@tanstack/react-query'
import { render, screen } from '@testing-library/react'
import { RouterProvider } from 'react-router-dom'
import { describe, expect, it } from 'vitest'
import { AppProviders } from '@/app/providers/app-providers'
import { createAppMemoryRouter } from '@/app/router/app-router'
import type { ClientCorrelationId } from '@/shared/observability/correlation'

const testCorrelationId = 'correlation-test' as ClientCorrelationId

function renderRoute(path: string) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  })
  const router = createAppMemoryRouter([path])

  render(
    <AppProviders
      clientCorrelationId={testCorrelationId}
      queryClient={queryClient}
      release={{ environment: 'test', releaseId: 'test-suite' }}
    >
      <RouterProvider router={router} />
    </AppProviders>,
  )
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
})
