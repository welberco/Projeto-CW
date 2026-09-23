import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { QueryClient } from '@tanstack/react-query'
import { RouterProvider } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import { AppProviders } from '@/app/providers/app-providers'
import { createAppMemoryRouter } from '@/app/router/app-router'
import { cadastroRoutes } from '@/app/pages/cadastros/cadastro-routes'
import type { AuthGateway } from '@/infrastructure/supabase/auth-gateway'
import type { AuthorizationGateway } from '@/infrastructure/supabase/authorization-gateway'
import type { ClientCorrelationId } from '@/shared/observability/correlation'
import type { AuthorizationProjectionResolution } from '@/shared/authorization/authorization-projection'
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

const authorizationGateway: AuthorizationGateway = {
  resolveProjection: () =>
    Promise.resolve({
      status: 'ready',
      projection: {
        principalId: 'principal-a',
        tenantId: 'tenant-a',
        tenantRef,
        membershipId: 'membership-a',
        profileId: 'profile-a',
        profileName: 'Gestor',
        revision: {
          membershipVersion: 1,
          profileVersion: 1,
          catalogRevision: 12,
        },
        authorizationRevision: 'm1:p1:c12',
        permissionCodes: [],
        enabledEntitlements: ['maintenance'],
      },
    }),
}

function withPermissions(permissionCodes: string[], enabledEntitlements = ['maintenance']): AuthorizationGateway {
  return {
    resolveProjection: () =>
      Promise.resolve({
        status: 'ready',
        projection: {
          principalId: 'principal-a', tenantId: 'tenant-a', tenantRef,
          membershipId: 'membership-a', profileId: 'profile-a', profileName: 'Gestor',
          revision: { membershipVersion: 1, profileVersion: 1, catalogRevision: 12 },
          authorizationRevision: 'm1:p1:c12', permissionCodes, enabledEntitlements,
        },
      }),
  }
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

function renderRoute(
  path: string,
  gateway = createGateway(),
  projectedAuthorizationGateway = authorizationGateway,
) {
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
      authorizationGateway={projectedAuthorizationGateway}
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
  it('shows only authorized cadastro groups and real links in the tenant shell', async () => {
    const { router } = renderRoute(
      `/e/${tenantRef}/cadastros`, createTenantGateway(),
      withPermissions(['shared.locations.read.all_tenant', 'shared.teams.read.team']),
    )
    expect(await screen.findByRole('heading', { name: 'Cadastros' })).toBeVisible()
    expect(screen.getByRole('region', { name: 'Estrutura' })).toBeVisible()
    expect(screen.getByRole('region', { name: 'Pessoas e Equipes' })).toBeVisible()
    expect(screen.queryByRole('region', { name: 'Manutenção' })).not.toBeInTheDocument()
    const nav = screen.getByRole('navigation', { name: 'Navegação principal' })
    expect(nav.querySelector('[aria-current="page"]')).toHaveTextContent('Cadastros')
    fireEvent.click(screen.getByRole('link', { name: 'Locais' }))
    expect(await screen.findByRole('heading', { name: 'Locais' })).toBeVisible()
    expect(router.state.location.pathname).toBe(`/e/${tenantRef}/cadastros/locais`)
    expect(nav.querySelector('[aria-current="page"]')).toHaveTextContent('Cadastros')
    await act(async () => router.navigate(-1))
    expect(await screen.findByRole('heading', { name: 'Cadastros' })).toBeVisible()
  })

  it('keeps the cadastro entry and route fail-closed for lookup-only grants', async () => {
    const { router } = renderRoute(
      `/e/${tenantRef}/cadastros`, createTenantGateway(),
      withPermissions(['shared.locations.lookup.all_tenant', 'shared.teams.lookup.team']),
    )
    expect(await screen.findByRole('heading', { name: 'Sem permissão' })).toBeVisible()
    expect(screen.queryByRole('link', { name: 'Cadastros' })).not.toBeInTheDocument()
    await act(async () => router.navigate(`/e/${tenantRef}/cadastros/locais`))
    expect(await screen.findByRole('heading', { name: 'Sem permissão' })).toBeVisible()
  })

  it('requires the exact page grant and entitlement without inferring other actions', async () => {
    renderRoute(
      `/e/${tenantRef}/manutencao/motivos`, createTenantGateway(),
      withPermissions(['maintenance.maintenance_reasons.read.all_tenant'], []),
    )
    expect(await screen.findByRole('heading', { name: 'Sem permissão' })).toBeVisible()
  })

  it('does not promote create, reactivate or membership add into page read', async () => {
    const { router } = renderRoute(
      `/e/${tenantRef}/cadastros/locais`, createTenantGateway(),
      withPermissions([
        'shared.locations.create.all_tenant',
        'shared.locations.reactivate.all_tenant',
        'shared.team_memberships.add.all_tenant',
      ]),
    )
    expect(await screen.findByRole('heading', { name: 'Sem permissão' })).toBeVisible()
    await act(async () => router.navigate(`/e/${tenantRef}/cadastros/equipes`))
    expect(await screen.findByRole('heading', { name: 'Sem permissão' })).toBeVisible()
  })

  it('treats TEAM and ALL_TENANT team read as independent exact alternatives', async () => {
    renderRoute(
      `/e/${tenantRef}/cadastros/equipes`, createTenantGateway(),
      withPermissions(['shared.teams.read.team']),
    )
    expect(await screen.findByRole('heading', { name: 'Equipes' })).toBeVisible()
    expect(screen.queryByRole('link', { name: 'Membros da Equipe' })).not.toBeInTheDocument()
  })

  it('marks Cadastros active on maintenance routes without exposing other groups', async () => {
    renderRoute(
      `/e/${tenantRef}/manutencao/motivos`, createTenantGateway(),
      withPermissions(['maintenance.maintenance_reasons.read.all_tenant']),
    )
    expect(await screen.findByRole('heading', { name: 'Motivos' })).toBeVisible()
    const nav = screen.getByRole('navigation', { name: 'Navegação principal' })
    expect(nav.querySelector('[aria-current="page"]')).toHaveTextContent('Cadastros')
  })

  it.each(cadastroRoutes)('resolves the frozen deep link $path without domain data', async (route) => {
    const path = route.path.replace(/:[^/]+/g, '34000000-0000-4000-8000-000000000010')
    const { router } = renderRoute(
      `/e/${tenantRef}/${path}`, createTenantGateway(),
      withPermissions([route.permissionCodes[0] ?? '']),
    )
    expect(await screen.findByRole('heading', { name: route.title })).toBeVisible()
    expect(screen.getByRole('heading', { name: 'Funcionalidade em preparação' })).toBeVisible()
    expect(router.state.location.pathname).toBe(`/e/${tenantRef}/${path}`)
  })

  it('rejects invalid detail identifiers after tenant validation', async () => {
    renderRoute(
      `/e/${tenantRef}/cadastros/locais/not-a-uuid`, createTenantGateway(),
      withPermissions(['shared.locations.read.all_tenant']),
    )
    expect(await screen.findByRole('heading', { name: 'Página não encontrada' })).toBeVisible()
  })

  it('keeps an unknown cadastro child on the validated tenant not-found route', async () => {
    renderRoute(`/e/${tenantRef}/cadastros/inexistente`, createTenantGateway(), withPermissions(['shared.locations.read.all_tenant']))
    expect(await screen.findByRole('heading', { name: 'Página não encontrada' })).toBeVisible()
  })

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

    await waitFor(() => {
      expect(completeContextResolution).toBeTypeOf('function')
    })
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

    await waitFor(() => {
      expect(completeTargetResolution).toBeTypeOf('function')
    })
    act(() => completeTargetResolution?.(readyResolution))
    expect(
      await screen.findByRole('heading', { name: 'Visão Geral' }),
    ).toBeVisible()
  })

  it('does not render tenant content before the authorization projection is ready', async () => {
    let completeProjection:
      | ((value: AuthorizationProjectionResolution) => void)
      | undefined
    const pendingAuthorizationGateway: AuthorizationGateway = {
      resolveProjection: () =>
        new Promise((resolve) => {
          completeProjection = resolve
        }),
    }

    renderRoute(
      `/e/${tenantRef}/dashboard`,
      createTenantGateway(),
      pendingAuthorizationGateway,
    )

    expect(
      await screen.findByRole('heading', { name: 'Carregando autorização' }),
    ).toBeVisible()
    expect(
      screen.queryByRole('heading', { name: 'Visão Geral' }),
    ).not.toBeInTheDocument()

    act(() =>
      completeProjection?.({
        status: 'ready',
        projection: {
          principalId: 'principal-a',
          tenantId: 'tenant-a',
          tenantRef,
          membershipId: 'membership-a',
          profileId: 'profile-a',
          profileName: 'Gestor',
          revision: {
            membershipVersion: 1,
            profileVersion: 1,
            catalogRevision: 12,
          },
          authorizationRevision: 'm1:p1:c12',
          permissionCodes: [],
          enabledEntitlements: ['maintenance'],
        },
      }),
    )
    expect(
      await screen.findByRole('heading', { name: 'Visão Geral' }),
    ).toBeVisible()
  })

  it('renders a generic fail-closed state when authorization is unavailable', async () => {
    const unavailableAuthorizationGateway: AuthorizationGateway = {
      resolveProjection: () =>
        Promise.resolve({
          status: 'profile_unavailable',
          principalId: 'principal-a',
        }),
    }
    renderRoute(
      `/e/${tenantRef}/dashboard`,
      createTenantGateway(),
      unavailableAuthorizationGateway,
    )

    expect(
      await screen.findByRole('heading', { name: 'Autorização indisponível' }),
    ).toBeVisible()
    expect(screen.queryByText('profile_unavailable')).not.toBeInTheDocument()
    expect(
      screen.queryByRole('heading', { name: 'Visão Geral' }),
    ).not.toBeInTheDocument()
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
