import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { QueryClient } from '@tanstack/react-query'
import { StrictMode } from 'react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { AuthorizationProvider } from '@/app/authorization/authorization-context'
import type {
  AuthorizationSignalBus,
  AuthorizationSignalType,
} from '@/app/authorization/authorization-signal'
import { useAuthorization } from '@/app/authorization/use-authorization'
import { AuthContext, type AuthContextValue } from '@/app/auth/use-auth'
import type { AuthorizationGateway } from '@/infrastructure/supabase/authorization-gateway'
import type {
  AuthorizationProjection,
  AuthorizationProjectionResolution,
} from '@/shared/authorization/authorization-projection'
import type { SessionState } from '@/shared/session/tenant-context'

function projection(
  principalId = 'principal-a',
  authorizationRevision = 'm1:p1:c12',
): AuthorizationProjection {
  const revisionMatch = authorizationRevision.match(/^m(\d+):p(\d+):c(\d+)$/)
  return {
    principalId,
    tenantId: `tenant-${principalId.at(-1)}`,
    tenantRef:
      principalId === 'principal-a'
        ? '34000000-0000-4000-8000-000000000001'
        : '34000000-0000-4000-8000-000000000002',
    membershipId: `membership-${principalId.at(-1)}`,
    profileId: `profile-${principalId.at(-1)}`,
    profileName: 'Gestor',
    revision: {
      membershipVersion: Number(revisionMatch?.[1] ?? 1),
      profileVersion: Number(revisionMatch?.[2] ?? 1),
      catalogRevision: Number(revisionMatch?.[3] ?? 12),
    },
    authorizationRevision,
    permissionCodes: ['core.users.read.all_tenant'],
    enabledEntitlements: ['maintenance'],
  }
}

function sessionFor(currentProjection: AuthorizationProjection): SessionState {
  return {
    status: 'ready',
    context: {
      principalId: currentProjection.principalId,
      tenantId: currentProjection.tenantId,
      tenantRef: currentProjection.tenantRef,
      tenantDisplayName: 'Tenant',
      membershipId: currentProjection.membershipId,
      membershipVersion: currentProjection.revision.membershipVersion,
      contextGeneration: 1,
    },
  }
}

function authValue(state: SessionState): AuthContextValue {
  return {
    state,
    signIn: vi.fn(() => Promise.resolve()),
    signOut: vi.fn(() => Promise.resolve()),
    acceptInvitation: vi.fn(() => Promise.resolve()),
    resolveTenantRef: vi.fn(() => Promise.resolve()),
    refreshSession: vi.fn(() => Promise.resolve()),
  }
}

function createSignalBus() {
  let listener: ((type: AuthorizationSignalType) => void) | undefined
  const publish = vi.fn()
  const bus: AuthorizationSignalBus = {
    publish,
    subscribe(nextListener) {
      listener = nextListener
      return () => {
        listener = undefined
      }
    },
    close: vi.fn(),
  }
  return { bus, emit: (type: AuthorizationSignalType) => listener?.(type), publish }
}

function AuthorizationProbe() {
  const authorization = useAuthorization()
  const currentProjection =
    authorization.state.status === 'ready'
      ? authorization.state.projection
      : undefined
  return (
    <div>
      <output aria-label="status">{authorization.state.status}</output>
      <output aria-label="principal">{currentProjection?.principalId ?? '-'}</output>
      <output aria-label="generation">
        {authorization.state.status === 'ready'
          ? authorization.state.authorizationGeneration
          : '-'}
      </output>
      <output aria-label="permission">
        {authorization.hasPermission('core.users.read.all_tenant') ? 'yes' : 'no'}
      </output>
      <button onClick={() => void authorization.refreshAuthorization()} type="button">
        Refresh
      </button>
      <button onClick={() => void authorization.invalidateAuthorization()} type="button">
        Invalidate
      </button>
    </div>
  )
}

function setup(
  gateway: AuthorizationGateway,
  initialSession = sessionFor(projection()),
  revalidationIntervalMs = 30_000,
) {
  const queryClient = new QueryClient()
  const cancelQueries = vi
    .spyOn(queryClient, 'cancelQueries')
    .mockResolvedValue(undefined)
  const signals = createSignalBus()
  const view = render(
    <AuthContext.Provider value={authValue(initialSession)}>
      <AuthorizationProvider
        gateway={gateway}
        queryClient={queryClient}
        signalBus={signals.bus}
        revalidationIntervalMs={revalidationIntervalMs}
      >
        <AuthorizationProbe />
      </AuthorizationProvider>
    </AuthContext.Provider>,
  )

  return {
    ...view,
    cancelQueries,
    queryClient,
    signals,
    rerenderSession(nextSession: SessionState) {
      view.rerender(
        <AuthContext.Provider value={authValue(nextSession)}>
          <AuthorizationProvider
            gateway={gateway}
            queryClient={queryClient}
            signalBus={signals.bus}
            revalidationIntervalMs={revalidationIntervalMs}
          >
            <AuthorizationProbe />
          </AuthorizationProvider>
        </AuthContext.Provider>,
      )
    },
  }
}

function sequentialGateway(
  resolutions: AuthorizationProjectionResolution[],
): AuthorizationGateway {
  let index = 0
  const fallback: AuthorizationProjectionResolution = {
    status: 'unauthenticated',
  }
  return {
    resolveProjection: vi.fn(() =>
      Promise.resolve(
        resolutions[Math.min(index++, resolutions.length - 1)] ?? fallback,
      ),
    ),
  }
}

afterEach(() => {
  vi.useRealTimers()
  vi.restoreAllMocks()
})

describe('authorization provider', () => {
  it('reaches ready after the production StrictMode effect replay', async () => {
    const currentProjection = projection()
    const gateway = sequentialGateway([
      { status: 'ready', projection: currentProjection },
    ])
    const signals = createSignalBus()

    render(
      <StrictMode>
        <AuthContext.Provider value={authValue(sessionFor(currentProjection))}>
          <AuthorizationProvider
            gateway={gateway}
            queryClient={new QueryClient()}
            signalBus={signals.bus}
          >
            <AuthorizationProbe />
          </AuthorizationProvider>
        </AuthContext.Provider>
      </StrictMode>,
    )

    expect(await screen.findByText('ready')).toBeVisible()
    expect(screen.getByLabelText('principal')).toHaveTextContent('principal-a')
  })

  it('loads the self projection and exposes exact fail-closed helpers', async () => {
    const gateway = sequentialGateway([{ status: 'ready', projection: projection() }])
    setup(gateway)

    expect(await screen.findByText('ready')).toBeVisible()
    expect(screen.getByLabelText('principal')).toHaveTextContent('principal-a')
    expect(screen.getByLabelText('generation')).toHaveTextContent('1')
    expect(screen.getByLabelText('permission')).toHaveTextContent('yes')
  })

  it('cancels and clears sensitive cache before accepting a changed revision', async () => {
    const changed = projection('principal-a', 'm1:p2:c12')
    const gateway = sequentialGateway([
      { status: 'ready', projection: projection() },
      { status: 'ready', projection: changed },
    ])
    const test = setup(gateway)
    expect(await screen.findByText('ready')).toBeVisible()
    test.queryClient.setQueryData(['sensitive'], { tenant: 'A' })

    fireEvent.click(screen.getByRole('button', { name: 'Refresh' }))

    await waitFor(() => expect(screen.getByLabelText('generation')).toHaveTextContent('2'))
    expect(test.cancelQueries).toHaveBeenCalledOnce()
    expect(test.queryClient.getQueryData(['sensitive'])).toBeUndefined()
  })

  it('centralizes command invalidation, signals other tabs and reconsults the backend', async () => {
    const gateway = sequentialGateway([{ status: 'ready', projection: projection() }])
    const test = setup(gateway)
    expect(await screen.findByText('ready')).toBeVisible()
    test.queryClient.setQueryData(['sensitive'], true)

    fireEvent.click(screen.getByRole('button', { name: 'Invalidate' }))

    await waitFor(() => expect(gateway.resolveProjection).toHaveBeenCalledTimes(2))
    expect(test.signals.publish).toHaveBeenCalledWith('authz-invalidated')
    expect(test.cancelQueries).toHaveBeenCalledOnce()
    expect(test.queryClient.getQueryData(['sensitive'])).toBeUndefined()
    expect(screen.getByLabelText('generation')).toHaveTextContent('2')
  })

  it('fails closed and removes prior capabilities when the backend becomes unavailable', async () => {
    const gateway = sequentialGateway([
      { status: 'ready', projection: projection() },
      { status: 'membership_unavailable', principalId: 'principal-a' },
    ])
    const test = setup(gateway)
    expect(await screen.findByText('ready')).toBeVisible()

    fireEvent.click(screen.getByRole('button', { name: 'Refresh' }))

    expect(await screen.findByText('unavailable')).toBeVisible()
    expect(screen.getByLabelText('permission')).toHaveTextContent('no')
    expect(test.cancelQueries).toHaveBeenCalledOnce()
  })

  it('never exposes principal A while switching to principal B', async () => {
    const projectionA = projection()
    const projectionB = projection('principal-b')
    const gateway = sequentialGateway([
      { status: 'ready', projection: projectionA },
      { status: 'ready', projection: projectionB },
    ])
    const test = setup(gateway, sessionFor(projectionA))
    expect(await screen.findByText('ready')).toBeVisible()

    test.rerenderSession(sessionFor(projectionB))
    expect(screen.getByLabelText('status')).not.toHaveTextContent('ready')
    expect(screen.getByLabelText('principal')).toHaveTextContent('-')

    await waitFor(() => expect(screen.getByLabelText('principal')).toHaveTextContent('principal-b'))
    expect(test.cancelQueries).toHaveBeenCalledOnce()
  })

  it('discards an older projection response after the principal changes', async () => {
    let resolveA: ((value: AuthorizationProjectionResolution) => void) | undefined
    let resolveB: ((value: AuthorizationProjectionResolution) => void) | undefined
    const gateway: AuthorizationGateway = {
      resolveProjection: vi
        .fn()
        .mockImplementationOnce(
          () =>
            new Promise<AuthorizationProjectionResolution>((resolve) => {
              resolveA = resolve
            }),
        )
        .mockImplementationOnce(
          () =>
            new Promise<AuthorizationProjectionResolution>((resolve) => {
              resolveB = resolve
            }),
        ),
    }
    const projectionB = projection('principal-b')
    const test = setup(gateway)

    test.rerenderSession(sessionFor(projectionB))
    await waitFor(() => expect(gateway.resolveProjection).toHaveBeenCalledTimes(2))
    await act(() => {
      resolveB?.({ status: 'ready', projection: projectionB })
      return Promise.resolve()
    })
    expect(screen.getByLabelText('principal')).toHaveTextContent('principal-b')

    await act(() => {
      resolveA?.({ status: 'ready', projection: projection() })
      return Promise.resolve()
    })
    expect(screen.getByLabelText('principal')).toHaveTextContent('principal-b')
  })

  it('reconsults on remote invalidation and clears immediately on remote sign-out', async () => {
    const gateway = sequentialGateway([{ status: 'ready', projection: projection() }])
    const test = setup(gateway)
    expect(await screen.findByText('ready')).toBeVisible()

    act(() => test.signals.emit('authz-invalidated'))
    await waitFor(() => expect(gateway.resolveProjection).toHaveBeenCalledTimes(2))
    expect(test.signals.publish).not.toHaveBeenCalled()

    act(() => test.signals.emit('signed-out'))
    expect(await screen.findByText('unauthenticated')).toBeVisible()
    expect(screen.getByLabelText('permission')).toHaveTextContent('no')
  })

  it('uses one visible interval, reacts to focus, pauses while hidden and cleans up', async () => {
    vi.useFakeTimers()
    const gateway = sequentialGateway([{ status: 'ready', projection: projection() }])
    const test = setup(gateway, sessionFor(projection()), 1_000)

    await act(async () => Promise.resolve())
    expect(gateway.resolveProjection).toHaveBeenCalledOnce()

    act(() => {
      window.dispatchEvent(new Event('focus'))
    })
    await act(async () => Promise.resolve())
    expect(gateway.resolveProjection).toHaveBeenCalledTimes(2)

    await act(async () => vi.advanceTimersByTimeAsync(1_000))
    expect(gateway.resolveProjection).toHaveBeenCalledTimes(3)
    expect(test.cancelQueries).not.toHaveBeenCalled()

    const hidden = vi.spyOn(document, 'hidden', 'get').mockReturnValue(true)
    act(() => {
      document.dispatchEvent(new Event('visibilitychange'))
    })
    await act(async () => vi.advanceTimersByTimeAsync(2_000))
    expect(gateway.resolveProjection).toHaveBeenCalledTimes(3)

    hidden.mockReturnValue(false)
    act(() => {
      document.dispatchEvent(new Event('visibilitychange'))
    })
    await act(async () => Promise.resolve())
    expect(gateway.resolveProjection).toHaveBeenCalledTimes(4)

    test.unmount()
    await act(async () => vi.advanceTimersByTimeAsync(2_000))
    expect(gateway.resolveProjection).toHaveBeenCalledTimes(4)
  })
})
