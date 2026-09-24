import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { QueryClient } from '@tanstack/react-query'
import { RouterProvider } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import { AppProviders } from '@/app/providers/app-providers'
import { createAppMemoryRouter } from '@/app/router/app-router'
import { cadastroRoutes } from '@/app/pages/cadastros/cadastro-routes'
import type { CadastroGateways } from '@/app/cadastros/cadastro-gateways-context'
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

const cadastroGateways = {
  structuralCatalog: {
    listLocationTypes: vi.fn(() => Promise.resolve([])), listLocations: vi.fn(() => Promise.resolve([])),
    listCostCenters: vi.fn(() => Promise.resolve([])), listSectors: vi.fn(() => Promise.resolve([])),
  },
  teams: {
    listTeams: vi.fn(() => Promise.resolve([])), listTeamMembers: vi.fn(() => Promise.resolve([])),
    lookupTeamMemberCandidates: vi.fn(() => Promise.resolve([])),
  },
} as unknown as CadastroGateways

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
  gateways = cadastroGateways,
) {
  const router = createAppMemoryRouter([path])
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: { retry: false },
      mutations: { retry: false },
    },
  })

  const rendered = render(
    <AppProviders
      authGateway={gateway}
      authorizationGateway={projectedAuthorizationGateway}
      cadastroGateways={gateways}
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

  return { queryClient, router, ...rendered }
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
    const functionalTitle = route.path.startsWith('cadastros/tipos-de-local') ? 'Tipos de Local'
      : route.path.startsWith('cadastros/locais') ? 'Locais'
        : route.path.startsWith('cadastros/centros-de-custo') ? 'Centros de Custo'
          : route.path.startsWith('cadastros/setores') ? 'Setores'
            : route.path.startsWith('cadastros/equipes') && !route.path.endsWith('/membros') ? 'Equipes'
              : route.title
    expect(await screen.findByRole('heading', { name: functionalTitle })).toBeVisible()
    if (route.path.startsWith('manutencao/') || route.path.startsWith('cadastros/tipos-de-documento')) {
      expect(screen.getByRole('heading', { name: 'Funcionalidade em preparação' })).toBeVisible()
    }
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

const recordId = '34000000-0000-4000-8000-000000000010'
const relatedId = '34000000-0000-4000-8000-000000000011'
const userId = '34000000-0000-4000-8000-000000000012'
const timestamp = '2026-09-24T12:00:00.000Z'

function functionalGateways(overrides: {
  structural?: Record<string, unknown>
  teams?: Record<string, unknown>
} = {}) {
  const structuralCatalog = {
    listLocationTypes: vi.fn(() => Promise.resolve([])), getLocationType: vi.fn(() => Promise.resolve(null)), lookupLocationTypes: vi.fn(() => Promise.resolve([{ id: relatedId, code: 'TIPO', name: 'Tipo A' }])), createLocationType: vi.fn(), updateLocationType: vi.fn(), inactivateLocationType: vi.fn(), reactivateLocationType: vi.fn(),
    listLocations: vi.fn(() => Promise.resolve([])), getLocation: vi.fn(() => Promise.resolve(null)), lookupLocations: vi.fn(() => Promise.resolve([])), createLocation: vi.fn(), updateLocation: vi.fn(), moveLocation: vi.fn(), inactivateLocation: vi.fn(), reactivateLocation: vi.fn(),
    listCostCenters: vi.fn(() => Promise.resolve([])), getCostCenter: vi.fn(() => Promise.resolve(null)), lookupCostCenters: vi.fn(() => Promise.resolve([])), createCostCenter: vi.fn(), updateCostCenter: vi.fn(), moveCostCenter: vi.fn(), inactivateCostCenter: vi.fn(), reactivateCostCenter: vi.fn(),
    listSectors: vi.fn(() => Promise.resolve([])), getSector: vi.fn(() => Promise.resolve(null)), lookupSectors: vi.fn(() => Promise.resolve([])), createSector: vi.fn(), updateSector: vi.fn(), inactivateSector: vi.fn(), reactivateSector: vi.fn(),
    ...overrides.structural,
  }
  const teams = {
    listTeams: vi.fn(() => Promise.resolve([])), getTeam: vi.fn(() => Promise.resolve(null)), createTeam: vi.fn(), updateTeam: vi.fn(), inactivateTeam: vi.fn(), reactivateTeam: vi.fn(),
    listTeamMembers: vi.fn(() => Promise.resolve([])), lookupTeamMemberCandidates: vi.fn(() => Promise.resolve([])), addTeamMember: vi.fn(), endTeamMember: vi.fn(),
    ...overrides.teams,
  }
  return { gateways: { structuralCatalog, teams } as unknown as CadastroGateways, structuralCatalog, teams }
}

const activeCatalogRow = { id: recordId, code: 'REG', name: 'Registro A', description: null, status: 'active' as const, version: 7, updated_at: timestamp }
const inactiveCatalogRow = { ...activeCatalogRow, status: 'inactive' as const }
const activeTeam = { id: recordId, sector_id: null, code: 'EQ', name: 'Equipe A', description: 'Descrição', status: 'active' as const, version: 9, updated_at: timestamp }
const activeMember = { id: relatedId, team_id: recordId, membership_id: '34000000-0000-4000-8000-000000000013', user_id: userId, display_name: 'Pessoa A', status: 'active' as const, joined_at: timestamp, ended_at: null, version: 4 }

describe('W4D.2.2 functional cadastro experience', () => {
  it.each([
    ['Tipos de Local', 'cadastros/tipos-de-local', 'shared.location_types.read.all_tenant', 'listLocationTypes'],
    ['Locais', 'cadastros/locais', 'shared.locations.read.all_tenant', 'listLocations'],
    ['Centros de Custo', 'cadastros/centros-de-custo', 'shared.cost_centers.read.all_tenant', 'listCostCenters'],
    ['Setores', 'cadastros/setores', 'shared.sectors.read.all_tenant', 'listSectors'],
  ] as const)('renders the real %s list through its exact read model', async (title, path, permission, method) => {
    const custom = functionalGateways({ structural: { [method]: vi.fn(() => Promise.resolve([activeCatalogRow])) } })
    renderRoute(`/e/${tenantRef}/${path}`, createTenantGateway(), withPermissions([permission]), custom.gateways)
    expect(await screen.findByRole('heading', { name: title })).toBeVisible()
    expect(await screen.findByText('Registro A')).toBeVisible()
    expect(screen.queryByRole('heading', { name: 'Funcionalidade em preparação' })).not.toBeInTheDocument()
    expect(custom.structuralCatalog[method]).toHaveBeenCalledOnce()
  })

  it('loads a structural detail by id instead of reusing the list query', async () => {
    const custom = functionalGateways({ structural: { getLocationType: vi.fn(() => Promise.resolve(activeCatalogRow)) } })
    renderRoute(`/e/${tenantRef}/cadastros/tipos-de-local/${recordId}`, createTenantGateway(), withPermissions(['shared.location_types.read.all_tenant']), custom.gateways)
    expect(await screen.findByText('Registro A')).toBeVisible()
    expect(custom.structuralCatalog.getLocationType).toHaveBeenCalledWith(recordId)
    expect(custom.structuralCatalog.listLocationTypes).not.toHaveBeenCalled()
  })

  it('shows structural actions only for their exact capabilities', async () => {
    const custom = functionalGateways({ structural: { listLocationTypes: vi.fn(() => Promise.resolve([activeCatalogRow])) } })
    renderRoute(`/e/${tenantRef}/cadastros/tipos-de-local`, createTenantGateway(), withPermissions(['shared.location_types.read.all_tenant', 'shared.location_types.create.all_tenant', 'shared.location_types.update.all_tenant', 'shared.location_types.inactivate.all_tenant']), custom.gateways)
    expect(await screen.findByRole('button', { name: 'Novo registro' })).toBeVisible()
    expect(await screen.findByRole('button', { name: 'Editar' })).toBeVisible()
    expect(screen.getByRole('button', { name: 'Inativar' })).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Reativar' })).not.toBeInTheDocument()
  })

  it('does not infer reactivate from read or update', async () => {
    const custom = functionalGateways({ structural: { listLocationTypes: vi.fn(() => Promise.resolve([inactiveCatalogRow])) } })
    renderRoute(`/e/${tenantRef}/cadastros/tipos-de-local`, createTenantGateway(), withPermissions(['shared.location_types.read.all_tenant', 'shared.location_types.update.all_tenant']), custom.gateways)
    expect(await screen.findByText('Registro A')).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Reativar' })).not.toBeInTheDocument()
  })

  it('offers reactivate only with the exact reactivate capability', async () => {
    const reactivateLocationType = vi.fn(() => Promise.resolve({ id: recordId, version: 8, status: 'active', command_correlation_id: relatedId }))
    const custom = functionalGateways({ structural: { listLocationTypes: vi.fn(() => Promise.resolve([inactiveCatalogRow])), reactivateLocationType } })
    renderRoute(`/e/${tenantRef}/cadastros/tipos-de-local`, createTenantGateway(), withPermissions(['shared.location_types.read.all_tenant', 'shared.location_types.reactivate.all_tenant']), custom.gateways)
    fireEvent.click(await screen.findByRole('button', { name: 'Reativar' })); fireEvent.click(screen.getByRole('button', { name: 'Confirmar' }))
    await waitFor(() => expect(reactivateLocationType).toHaveBeenCalledWith(expect.objectContaining({ id: recordId, expectedVersion: 7 })))
  })

  it('creates a structural record only after an accessible validated form submit', async () => {
    const createLocationType = vi.fn(() => Promise.resolve({ id: recordId, version: 1, status: 'active', command_correlation_id: relatedId }))
    const custom = functionalGateways({ structural: { createLocationType } })
    renderRoute(`/e/${tenantRef}/cadastros/tipos-de-local`, createTenantGateway(), withPermissions(['shared.location_types.read.all_tenant', 'shared.location_types.create.all_tenant']), custom.gateways)
    fireEvent.click(await screen.findByRole('button', { name: 'Novo registro' }))
    const form = screen.getByRole('form', { name: 'Criar Tipos de Local' })
    fireEvent.change(within(form).getByLabelText('Código'), { target: { value: 'TIPO' } }); fireEvent.change(within(form).getByLabelText('Nome'), { target: { value: 'Tipo A' } }); fireEvent.change(within(form).getByLabelText('Motivo'), { target: { value: 'Cadastro inicial' } })
    fireEvent.click(within(form).getByRole('button', { name: 'Criar registro' }))
    await waitFor(() => expect(createLocationType).toHaveBeenCalledWith(expect.objectContaining({ code: 'TIPO', name: 'Tipo A' })))
    expect(await screen.findByText('Alteração concluída.')).toBeVisible()
  })

  it('forwards the authoritative version on update and refetches after success', async () => {
    const listLocationTypes = vi.fn(() => Promise.resolve([activeCatalogRow])); const updateLocationType = vi.fn(() => Promise.resolve({ id: recordId, version: 8, status: 'active', command_correlation_id: relatedId }))
    const custom = functionalGateways({ structural: { listLocationTypes, updateLocationType } })
    renderRoute(`/e/${tenantRef}/cadastros/tipos-de-local`, createTenantGateway(), withPermissions(['shared.location_types.read.all_tenant', 'shared.location_types.update.all_tenant']), custom.gateways)
    fireEvent.click(await screen.findByRole('button', { name: 'Editar' })); const form = screen.getByRole('form', { name: 'Editar Registro A' }); fireEvent.change(within(form).getByLabelText('Motivo'), { target: { value: 'Correção' } }); fireEvent.click(within(form).getByRole('button', { name: 'Salvar alterações' }))
    await waitFor(() => expect(updateLocationType).toHaveBeenCalledWith(expect.objectContaining({ id: recordId, expectedVersion: 7 })))
    await waitFor(() => expect(listLocationTypes.mock.calls.length).toBeGreaterThan(1))
  })

  it('refetches authoritative state and never reports success after a stale update', async () => {
    const listLocationTypes = vi.fn(() => Promise.resolve([activeCatalogRow])); const updateLocationType = vi.fn(() => Promise.reject(new Error('VERSION_CONFLICT internal detail')))
    const custom = functionalGateways({ structural: { listLocationTypes, updateLocationType } })
    renderRoute(`/e/${tenantRef}/cadastros/tipos-de-local`, createTenantGateway(), withPermissions(['shared.location_types.read.all_tenant', 'shared.location_types.update.all_tenant']), custom.gateways)
    fireEvent.click(await screen.findByRole('button', { name: 'Editar' })); const form = screen.getByRole('form', { name: 'Editar Registro A' }); fireEvent.change(within(form).getByLabelText('Motivo'), { target: { value: 'Correção' } }); fireEvent.click(within(form).getByRole('button', { name: 'Salvar alterações' }))
    expect(await screen.findByText('Não foi possível concluir esta operação com segurança.')).toBeVisible()
    expect(screen.queryByText('VERSION_CONFLICT internal detail')).not.toBeInTheDocument()
    await waitFor(() => expect(listLocationTypes.mock.calls.length).toBeGreaterThan(1))
  })

  it('moves a Location with its read version through the existing W4A command', async () => {
    const location = { ...activeCatalogRow, location_type_id: relatedId, parent_id: null }; const moveLocation = vi.fn(() => Promise.resolve({ id: recordId, version: 8, status: 'active', command_correlation_id: relatedId }))
    const custom = functionalGateways({ structural: { listLocations: vi.fn(() => Promise.resolve([location])), lookupLocations: vi.fn(() => Promise.resolve([{ id: relatedId, code: null, name: 'Local pai' }])), moveLocation } })
    renderRoute(`/e/${tenantRef}/cadastros/locais`, createTenantGateway(), withPermissions(['shared.locations.read.all_tenant', 'shared.locations.move.all_tenant', 'shared.locations.lookup.all_tenant']), custom.gateways)
    fireEvent.click(await screen.findByRole('button', { name: 'Alterar vínculo' })); fireEvent.change(screen.getByLabelText('Novo vínculo superior'), { target: { value: relatedId } }); fireEvent.click(screen.getByRole('button', { name: 'Salvar vínculo' }))
    await waitFor(() => expect(moveLocation).toHaveBeenCalledWith(expect.objectContaining({ id: recordId, expectedVersion: 7, parentId: relatedId })))
  })

  it('requires explicit confirmation before inactivation', async () => {
    const inactivateLocationType = vi.fn(() => Promise.resolve({ id: recordId, version: 8, status: 'inactive', command_correlation_id: relatedId })); const custom = functionalGateways({ structural: { listLocationTypes: vi.fn(() => Promise.resolve([activeCatalogRow])), inactivateLocationType } })
    renderRoute(`/e/${tenantRef}/cadastros/tipos-de-local`, createTenantGateway(), withPermissions(['shared.location_types.read.all_tenant', 'shared.location_types.inactivate.all_tenant']), custom.gateways)
    fireEvent.click(await screen.findByRole('button', { name: 'Inativar' })); expect(inactivateLocationType).not.toHaveBeenCalled(); fireEvent.click(screen.getByRole('button', { name: 'Confirmar' }))
    await waitFor(() => expect(inactivateLocationType).toHaveBeenCalledWith(expect.objectContaining({ expectedVersion: 7 })))
  })

  it('renders the real Team list and detail read models', async () => {
    const custom = functionalGateways({ teams: { listTeams: vi.fn(() => Promise.resolve([activeTeam])), getTeam: vi.fn(() => Promise.resolve(activeTeam)) } })
    const { router } = renderRoute(`/e/${tenantRef}/cadastros/equipes`, createTenantGateway(), withPermissions(['shared.teams.read.all_tenant']), custom.gateways)
    fireEvent.click(await screen.findByRole('link', { name: 'Abrir equipe' })); expect(await screen.findByText('Equipe A')).toBeVisible(); expect(router.state.location.pathname).toContain(recordId); expect(custom.teams.getTeam).toHaveBeenCalledWith(recordId)
  })

  it('keeps Team create, update and lifecycle actions on exact independent capabilities', async () => {
    const custom = functionalGateways({ teams: { listTeams: vi.fn(() => Promise.resolve([activeTeam])) } })
    renderRoute(`/e/${tenantRef}/cadastros/equipes`, createTenantGateway(), withPermissions(['shared.teams.read.all_tenant', 'shared.teams.create.all_tenant', 'shared.teams.inactivate.all_tenant']), custom.gateways)
    expect(await screen.findByRole('button', { name: 'Nova equipe' })).toBeVisible(); expect(screen.getByRole('button', { name: 'Inativar' })).toBeVisible(); expect(screen.queryByRole('button', { name: 'Editar' })).not.toBeInTheDocument(); expect(screen.queryByRole('button', { name: 'Reativar' })).not.toBeInTheDocument()
  })

  it('does not infer Team reactivate from update', async () => {
    const custom = functionalGateways({ teams: { listTeams: vi.fn(() => Promise.resolve([{ ...activeTeam, status: 'inactive' }])) } })
    renderRoute(`/e/${tenantRef}/cadastros/equipes`, createTenantGateway(), withPermissions(['shared.teams.read.all_tenant', 'shared.teams.update.all_tenant']), custom.gateways)
    expect(await screen.findByText('Equipe A')).toBeVisible(); expect(screen.queryByRole('button', { name: 'Reativar' })).not.toBeInTheDocument()
  })

  it('forwards Team version and invalidates list/detail after update', async () => {
    const getTeam = vi.fn(() => Promise.resolve(activeTeam)); const updateTeam = vi.fn(() => Promise.resolve({ id: recordId, version: 10, status: 'active', command_correlation_id: relatedId })); const custom = functionalGateways({ teams: { getTeam, updateTeam } })
    renderRoute(`/e/${tenantRef}/cadastros/equipes/${recordId}`, createTenantGateway(), withPermissions(['shared.teams.read.all_tenant', 'shared.teams.update.all_tenant']), custom.gateways)
    fireEvent.click(await screen.findByRole('button', { name: 'Editar' })); const form = screen.getByRole('form', { name: 'Editar Equipe A' }); fireEvent.change(within(form).getByLabelText('Motivo'), { target: { value: 'Atualização' } }); fireEvent.click(within(form).getByRole('button', { name: 'Salvar equipe' }))
    await waitFor(() => expect(updateTeam).toHaveBeenCalledWith(expect.objectContaining({ id: recordId, expectedVersion: 9 }))); await waitFor(() => expect(getTeam.mock.calls.length).toBeGreaterThan(1))
  })

  it('does not call candidate lookup or expose add without add.all_tenant', async () => {
    const custom = functionalGateways({ teams: { listTeamMembers: vi.fn(() => Promise.resolve([activeMember])) } })
    renderRoute(`/e/${tenantRef}/cadastros/equipes/${recordId}/membros`, createTenantGateway(), withPermissions(['shared.team_memberships.read.all_tenant']), custom.gateways)
    expect(await screen.findByText('Pessoa A')).toBeVisible(); expect(screen.queryByRole('region', { name: 'Adicionar membro' })).not.toBeInTheDocument(); expect(screen.queryByRole('button', { name: 'Encerrar vínculo' })).not.toBeInTheDocument(); expect(custom.teams.lookupTeamMemberCandidates).not.toHaveBeenCalled()
  })

  it('handles null display name and sends the selected membership_id to add_team_member', async () => {
    const candidateMembershipId = '34000000-0000-4000-8000-000000000014'; const addTeamMember = vi.fn(() => Promise.resolve({ id: relatedId, version: 1, status: 'active', command_correlation_id: recordId })); const custom = functionalGateways({ teams: { lookupTeamMemberCandidates: vi.fn(() => Promise.resolve([{ membership_id: candidateMembershipId, user_id: userId, display_name: null }])), addTeamMember } })
    renderRoute(`/e/${tenantRef}/cadastros/equipes/${recordId}/membros`, createTenantGateway(), withPermissions(['shared.team_memberships.read.all_tenant', 'shared.team_memberships.add.all_tenant']), custom.gateways)
    fireEvent.click(await screen.findByRole('button', { name: 'Usuário sem nome de exibição' })); fireEvent.click(screen.getByRole('button', { name: 'Adicionar membro' }))
    await waitFor(() => expect(addTeamMember).toHaveBeenCalledWith(expect.objectContaining({ teamId: recordId, membershipId: candidateMembershipId })))
    expect(addTeamMember).toHaveBeenCalledWith(expect.not.objectContaining({ userId }))
  })

  it('shows candidate empty and error states without promoting the lookup', async () => {
    const empty = functionalGateways(); const { unmount } = renderRoute(`/e/${tenantRef}/cadastros/equipes/${recordId}/membros`, createTenantGateway(), withPermissions(['shared.team_memberships.read.all_tenant', 'shared.team_memberships.add.all_tenant']), empty.gateways)
    expect(await screen.findByText('Nenhum candidato disponível.')).toBeVisible(); unmount()
    const failing = functionalGateways({ teams: { lookupTeamMemberCandidates: vi.fn(() => Promise.reject(new Error('internal'))) } }); renderRoute(`/e/${tenantRef}/cadastros/equipes/${recordId}/membros`, createTenantGateway(), withPermissions(['shared.team_memberships.read.all_tenant', 'shared.team_memberships.add.all_tenant']), failing.gateways)
    expect(await screen.findByRole('alert')).toHaveTextContent('Não foi possível consultar candidatos.')
  })

  it('refetches candidates and roster after an invalid candidate add', async () => {
    const lookup = vi.fn(() => Promise.resolve([{ membership_id: relatedId, user_id: userId, display_name: 'Pessoa A' }])); const roster = vi.fn(() => Promise.resolve([])); const addTeamMember = vi.fn(() => Promise.reject(new Error('candidate stale'))); const custom = functionalGateways({ teams: { lookupTeamMemberCandidates: lookup, listTeamMembers: roster, addTeamMember } })
    renderRoute(`/e/${tenantRef}/cadastros/equipes/${recordId}/membros`, createTenantGateway(), withPermissions(['shared.team_memberships.read.all_tenant', 'shared.team_memberships.add.all_tenant']), custom.gateways)
    fireEvent.click(await screen.findByRole('button', { name: 'Pessoa A' })); fireEvent.click(screen.getByRole('button', { name: 'Adicionar membro' })); expect(await screen.findByText('Não foi possível concluir esta operação com segurança.')).toBeVisible(); await waitFor(() => expect(lookup.mock.calls.length).toBeGreaterThan(1)); expect(roster.mock.calls.length).toBeGreaterThan(1)
  })

  it('requires the exact end permission, confirms and forwards membership version', async () => {
    const listTeamMembers = vi.fn(() => Promise.resolve([activeMember])); const endTeamMember = vi.fn(() => Promise.resolve({ id: relatedId, version: 5, status: 'ended', command_correlation_id: recordId })); const custom = functionalGateways({ teams: { listTeamMembers, endTeamMember } })
    renderRoute(`/e/${tenantRef}/cadastros/equipes/${recordId}/membros`, createTenantGateway(), withPermissions(['shared.team_memberships.read.all_tenant', 'shared.team_memberships.end.all_tenant']), custom.gateways)
    fireEvent.click(await screen.findByRole('button', { name: 'Encerrar vínculo' })); expect(endTeamMember).not.toHaveBeenCalled(); fireEvent.click(screen.getByRole('button', { name: 'Confirmar' })); await waitFor(() => expect(endTeamMember).toHaveBeenCalledWith(expect.objectContaining({ id: relatedId, expectedVersion: 4 }))); await waitFor(() => expect(listTeamMembers.mock.calls.length).toBeGreaterThan(1))
  })

  it('shows loading, empty and safe error states for authoritative reads', async () => {
    let resolveList: ((value: never[]) => void) | undefined; const pending = functionalGateways({ structural: { listSectors: vi.fn(() => new Promise<never[]>((resolve) => { resolveList = resolve })) } }); const first = renderRoute(`/e/${tenantRef}/cadastros/setores`, createTenantGateway(), withPermissions(['shared.sectors.read.all_tenant']), pending.gateways)
    expect(await screen.findByRole('heading', { name: 'Carregando registros' })).toBeVisible(); act(() => resolveList?.([])); expect(await screen.findByRole('heading', { name: 'Nenhum registro encontrado' })).toBeVisible(); first.unmount()
    const failed = functionalGateways({ structural: { listSectors: vi.fn(() => Promise.reject(new Error('SQL private'))) } }); renderRoute(`/e/${tenantRef}/cadastros/setores`, createTenantGateway(), withPermissions(['shared.sectors.read.all_tenant']), failed.gateways); expect(await screen.findByRole('heading', { name: 'Não foi possível carregar os registros' })).toBeVisible(); expect(screen.queryByText('SQL private')).not.toBeInTheDocument()
  })

  it('uses principal, tenant and membership isolation in every tenant query key', async () => {
    const custom = functionalGateways(); const { queryClient } = renderRoute(`/e/${tenantRef}/cadastros/setores`, createTenantGateway(), withPermissions(['shared.sectors.read.all_tenant']), custom.gateways); await screen.findByRole('heading', { name: 'Nenhum registro encontrado' }); const key = queryClient.getQueryCache().getAll()[0]?.queryKey; expect(key).toEqual(expect.arrayContaining(['principal', 'principal-a', 'tenant', 'tenant-a', 'membership', 'membership-a']))
  })
})
