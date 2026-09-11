import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { QueryClient } from '@tanstack/react-query'
import { RouterProvider } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import { AppProviders } from '@/app/providers/app-providers'
import { createAppMemoryRouter } from '@/app/router/app-router'
import type { AuthGateway } from '@/infrastructure/supabase/auth-gateway'
import type { ClientCorrelationId } from '@/shared/observability/correlation'
import type { TenantContextResolution } from '@/shared/session/tenant-context'

const tenantRef = '34000000-0000-4000-8000-000000000001'
const otherTenantRef = '34000000-0000-4000-8000-000000000002'
const readyResolution: TenantContextResolution = {
  status: 'ready',
  context: {
    principalId: 'principal-a',
    tenantId: 'tenant-a',
    tenantRef,
    tenantDisplayName: 'Empreendimento A',
    membershipId: 'membership-a',
    membershipVersion: 1,
  },
}

function createGateway(
  resolveSession: AuthGateway['resolveSession'] = () =>
    Promise.resolve({ status: 'unauthenticated' }),
): AuthGateway {
  return {
    resolveSession,
    signIn: vi.fn(() => Promise.resolve()),
    signOut: vi.fn(() => Promise.resolve()),
    acceptInvitation: vi.fn(() => Promise.resolve()),
    onAuthChange: () => () => undefined,
  }
}

function renderRoute(path: string, gateway = createGateway()) {
  const router = createAppMemoryRouter([path])
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: { retry: false },
      mutations: { retry: false },
    },
  })

  render(
    <AppProviders
      authGateway={gateway}
      clientCorrelationId={'correlation-test' as ClientCorrelationId}
      queryClient={queryClient}
      release={{ environment: 'test', releaseId: 'w1d-test' }}
      routerCoordinator={{
        navigateToLogin: () => {
          void router.navigate('/login', { replace: true })
        },
        revalidate: () => {
          void router.revalidate()
        },
      }}
    >
      <RouterProvider router={router} />
    </AppProviders>,
  )

  return { queryClient, router }
}

function createTenantGateway() {
  return createGateway((targetTenantRef) =>
    Promise.resolve(
      targetTenantRef === undefined ||
        targetTenantRef === null ||
        targetTenantRef === tenantRef
        ? readyResolution
        : {
            status: 'tenant_context_unavailable',
            principalId: 'principal-a',
          },
    ),
  )
}

describe('app router', () => {
  it('redirects the unauthenticated root route to login', async () => {
    const { router } = renderRoute('/')

    expect(await screen.findByRole('heading', { name: 'Entrar' })).toBeVisible()
    expect(router.state.location.pathname).toBe('/login')
  })

  it('redirects login to the canonical tenant route only after a valid sign-in context', async () => {
    let authenticated = false
    const gateway = createGateway((targetTenantRef) =>
      Promise.resolve(
        authenticated || targetTenantRef !== undefined
          ? readyResolution
          : { status: 'unauthenticated' },
      ),
    )
    gateway.signIn = vi.fn(() => {
      authenticated = true
      return Promise.resolve()
    })
    const { router } = renderRoute('/login', gateway)

    fireEvent.change(await screen.findByLabelText('E-mail'), {
      target: { value: 'person@example.invalid' },
    })
    fireEvent.change(screen.getByLabelText('Senha'), {
      target: { value: 'not-a-real-password' },
    })
    fireEvent.click(screen.getByRole('button', { name: 'Entrar' }))

    expect(
      await screen.findByRole('heading', { name: 'Visão Geral' }),
    ).toBeVisible()
    expect(router.state.location.pathname).toBe(`/e/${tenantRef}/dashboard`)
    expect(gateway.signIn).toHaveBeenCalledOnce()
  })

  it('does not leave login while the post-authentication context is unresolved', async () => {
    let authenticated = false
    let completeContextResolution:
      | ((value: TenantContextResolution) => void)
      | undefined
    const gateway = createGateway((targetTenantRef) => {
      if (!authenticated) return Promise.resolve({ status: 'unauthenticated' })
      if (targetTenantRef !== undefined && targetTenantRef !== null) {
        return Promise.resolve(readyResolution)
      }
      return new Promise((resolve) => {
        completeContextResolution = resolve
      })
    })
    gateway.signIn = vi.fn(() => {
      authenticated = true
      return Promise.resolve()
    })
    const { router } = renderRoute('/login', gateway)

    fireEvent.change(await screen.findByLabelText('E-mail'), {
      target: { value: 'person@example.invalid' },
    })
    fireEvent.change(screen.getByLabelText('Senha'), {
      target: { value: 'not-a-real-password' },
    })
    fireEvent.click(screen.getByRole('button', { name: 'Entrar' }))

    expect(
      await screen.findByRole('heading', { name: 'Carregando acesso' }),
    ).toBeVisible()
    expect(router.state.location.pathname).toBe('/login')
    expect(
      screen.queryByRole('heading', { name: 'Visão Geral' }),
    ).not.toBeInTheDocument()

    act(() => completeContextResolution?.(readyResolution))
    expect(
      await screen.findByRole('heading', { name: 'Visão Geral' }),
    ).toBeVisible()
  })

  it('keeps an unauthenticated tenant deep link fail-closed', async () => {
    renderRoute(`/e/${tenantRef}/dashboard`)

    expect(
      await screen.findByRole('heading', { name: 'Autenticação necessária' }),
    ).toBeInTheDocument()
    expect(
      screen.queryByRole('heading', { name: 'Visão Geral' }),
    ).not.toBeInTheDocument()
  })

  it('does not render tenant content before the route context is validated', async () => {
    let completeTargetResolution:
      | ((value: TenantContextResolution) => void)
      | undefined
    const gateway = createGateway((targetTenantRef) => {
      if (targetTenantRef === undefined || targetTenantRef === null) {
        return Promise.resolve(readyResolution)
      }
      return new Promise((resolve) => {
        completeTargetResolution = resolve
      })
    })

    renderRoute(`/e/${tenantRef}/dashboard`, gateway)

    expect(
      await screen.findByRole('heading', { name: 'Carregando acesso' }),
    ).toBeVisible()
    expect(
      screen.queryByRole('heading', { name: 'Visão Geral' }),
    ).not.toBeInTheDocument()

    act(() => completeTargetResolution?.(readyResolution))
    expect(
      await screen.findByRole('heading', { name: 'Visão Geral' }),
    ).toBeVisible()
  })

  it('redirects the tenant index to the canonical dashboard route', async () => {
    const { router } = renderRoute(`/e/${tenantRef}`, createTenantGateway())

    expect(
      await screen.findByRole('heading', { name: 'Visão Geral' }),
    ).toBeVisible()
    expect(router.state.location.pathname).toBe(`/e/${tenantRef}/dashboard`)
  })

  it('renders the authenticated shell and account route only for a validated context', async () => {
    renderRoute(`/e/${tenantRef}/minha-conta`, createTenantGateway())

    expect(
      await screen.findByRole('heading', { name: 'Minha Conta' }),
    ).toBeVisible()
    expect(screen.getByText('Empreendimento A')).toBeVisible()
    expect(
      screen.getByRole('navigation', { name: 'Navegação principal' }),
    ).toBeVisible()
  })

  it('fails closed without enumerating a mismatched tenant reference', async () => {
    renderRoute(`/e/${otherTenantRef}/dashboard`, createTenantGateway())

    expect(
      await screen.findByRole('heading', { name: 'Contexto indisponível' }),
    ).toBeVisible()
    expect(screen.queryByText(otherTenantRef)).not.toBeInTheDocument()
    expect(screen.queryByText('Empreendimento A')).not.toBeInTheDocument()
    expect(
      screen.queryByRole('heading', { name: 'Visão Geral' }),
    ).not.toBeInTheDocument()
  })

  it.each([
    ['profile_missing', 'Identidade indisponível'],
    ['principal_unavailable', 'Usuário bloqueado ou inativo'],
    ['no_membership', 'Vínculo não encontrado'],
    ['membership_unavailable', 'Vínculo indisponível'],
    ['tenant_unavailable', 'Empreendimento indisponível'],
    ['feature_unavailable', 'Módulo indisponível'],
    ['error', 'Não foi possível verificar o acesso'],
  ] as const)('renders the safe %s route state', async (status, heading) => {
    const gateway =
      status === 'error'
        ? createGateway(() => Promise.reject(new Error('internal detail')))
        : createGateway(() =>
            Promise.resolve({ status, principalId: 'principal-a' }),
          )
    renderRoute(`/e/${tenantRef}/dashboard`, gateway)

    expect(await screen.findByRole('heading', { name: heading })).toBeVisible()
    expect(screen.queryByText(/internal detail/iu)).not.toBeInTheDocument()
  })

  it('protects the platform namespace without implementing Global Admin', async () => {
    renderRoute('/plataforma')

    expect(
      await screen.findByRole('heading', { name: 'Autenticação necessária' }),
    ).toBeVisible()
    expect(screen.queryByText(/bypass/iu)).not.toBeInTheDocument()
  })

  it('renders a safe not-found only after validating a tenant context', async () => {
    renderRoute(`/e/${tenantRef}/rota-inexistente`, createTenantGateway())

    expect(
      await screen.findByRole('heading', { name: 'Página não encontrada' }),
    ).toBeVisible()
    expect(screen.getByText('Empreendimento A')).toBeVisible()
  })

  it('clears protected content and cache before logout navigation', async () => {
    const gateway = createTenantGateway()
    const { queryClient, router } = renderRoute(
      `/e/${tenantRef}/dashboard`,
      gateway,
    )
    expect(
      await screen.findByRole('heading', { name: 'Visão Geral' }),
    ).toBeVisible()
    queryClient.setQueryData(['tenant-owned'], { tenant: 'A' })

    fireEvent.click(screen.getByRole('button', { name: 'Sair' }))

    expect(await screen.findByRole('heading', { name: 'Entrar' })).toBeVisible()
    expect(queryClient.getQueryData(['tenant-owned'])).toBeUndefined()
    expect(router.state.location.pathname).toBe('/login')
    expect(gateway.signOut).toHaveBeenCalledOnce()

    await act(async () => router.navigate(-1))
    await waitFor(() => {
      expect(
        screen.queryByRole('heading', { name: 'Visão Geral' }),
      ).not.toBeInTheDocument()
    })
  })

  it('renders a safe public not-found state', async () => {
    renderRoute('/rota-inexistente')

    expect(
      await screen.findByRole('heading', { name: 'Página não encontrada' }),
    ).toBeVisible()
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
