import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import type { AuthChangeEvent } from '@supabase/supabase-js'
import { QueryClient } from '@tanstack/react-query'
import { describe, expect, it, vi } from 'vitest'
import { SessionProvider } from '@/app/auth/auth-context'
import { useAuth } from '@/app/auth/use-auth'
import type { AuthGateway } from '@/infrastructure/supabase/auth-gateway'
import type { TenantContextResolution } from '@/shared/session/tenant-context'

const readyA: TenantContextResolution = {
  status: 'ready',
  context: {
    principalId: 'principal-a',
    tenantId: 'tenant-a',
    tenantRef: '34000000-0000-4000-8000-000000000001',
    tenantDisplayName: 'Tenant A',
    membershipId: 'membership-a',
    membershipVersion: 1,
  },
}

function SessionProbe() {
  const { state, signOut } = useAuth()
  const generation =
    state.status === 'ready' ? state.context.contextGeneration : '-'
  return (
    <div>
      <output>{state.status}</output>
      <output aria-label="generation">{generation}</output>
      <button onClick={() => void signOut()} type="button">Sign out</button>
    </div>
  )
}

function setup(resolutions: TenantContextResolution[]) {
  let listener: ((event: AuthChangeEvent) => void) | undefined
  let resolutionIndex = 0
  const events: string[] = []
  const queryClient = new QueryClient()
  queryClient.setQueryData(['sensitive'], { tenant: 'A' })
  const cancelQueries = vi
    .spyOn(queryClient, 'cancelQueries')
    .mockImplementation(() => {
      events.push('cancel')
      return Promise.resolve()
    })
  const signOut = vi.fn(() => {
    events.push('signOut')
    return Promise.resolve()
  })
  const navigateToLogin = vi.fn(() => {
    events.push('navigate')
  })
  const revalidate = vi.fn()
  const publishAuthorizationSignal = vi.fn()
  const gateway: AuthGateway = {
    resolveSession: vi.fn((): Promise<TenantContextResolution> => {
      const resolution =
        resolutions[Math.min(resolutionIndex++, resolutions.length - 1)]
      return Promise.resolve(resolution ?? { status: 'unauthenticated' })
    }),
    signIn: vi.fn(() => Promise.resolve()),
    signOut,
    acceptInvitation: vi.fn(() => Promise.resolve()),
    onAuthChange(nextListener) {
      listener = nextListener
      return () => undefined
    },
  }

  render(
    <SessionProvider
      authorizationSignals={{
        publish: publishAuthorizationSignal,
        subscribe: () => () => undefined,
        close: () => undefined,
      }}
      gateway={gateway}
      queryClient={queryClient}
      routerCoordinator={{ navigateToLogin, revalidate }}
    >
      <SessionProbe />
    </SessionProvider>,
  )

  return {
    cancelQueries,
    events,
    gateway,
    getListener: () => listener,
    navigateToLogin,
    publishAuthorizationSignal,
    queryClient,
    revalidate,
    signOut,
  }
}

describe('session provider lifecycle', () => {
  it('revalidates on Auth refresh without rotating an unchanged context generation', async () => {
    const test = setup([readyA, readyA])
    expect(await screen.findByText('ready')).toBeVisible()
    expect(screen.getByLabelText('generation')).toHaveTextContent('1')

    act(() => test.getListener()?.('TOKEN_REFRESHED'))

    await waitFor(() => expect(test.gateway.resolveSession).toHaveBeenCalledTimes(2))
    expect(await screen.findByText('ready')).toBeVisible()
    expect(screen.getByLabelText('generation')).toHaveTextContent('1')
    expect(test.revalidate).toHaveBeenCalledOnce()
  })

  it('cancels and clears tenant cache when Auth changes principal', async () => {
    const readyB: TenantContextResolution = {
      ...readyA,
      context: { ...readyA.context, principalId: 'principal-b' },
    }
    const test = setup([readyA, readyB])
    expect(await screen.findByText('ready')).toBeVisible()
    expect(test.queryClient.getQueryData(['sensitive'])).toEqual({ tenant: 'A' })

    act(() => test.getListener()?.('SIGNED_IN'))

    await waitFor(() => expect(test.cancelQueries).toHaveBeenCalledOnce())
    expect(test.queryClient.getQueryData(['sensitive'])).toBeUndefined()
    expect(screen.getByLabelText('generation')).toHaveTextContent('2')
  })

  it('clears tenant cache when the persisted membership version changes', async () => {
    const changedMembership: TenantContextResolution = {
      ...readyA,
      context: { ...readyA.context, membershipVersion: 2 },
    }
    const test = setup([readyA, changedMembership])
    expect(await screen.findByText('ready')).toBeVisible()

    act(() => test.getListener()?.('USER_UPDATED'))

    await waitFor(() => expect(test.cancelQueries).toHaveBeenCalledOnce())
    expect(test.queryClient.getQueryData(['sensitive'])).toBeUndefined()
    expect(screen.getByLabelText('generation')).toHaveTextContent('2')
  })

  it.each([
    ['principal_unavailable', { status: 'principal_unavailable', principalId: 'principal-a' }],
    ['membership_unavailable', { status: 'membership_unavailable', principalId: 'principal-a' }],
    ['tenant_unavailable', { status: 'tenant_unavailable', principalId: 'principal-a' }],
    ['unauthenticated', { status: 'unauthenticated' }],
  ] satisfies Array<[string, TenantContextResolution]>) (
    'clears tenant cache when revalidation returns %s',
    async (status, invalidatedResolution) => {
      const test = setup([readyA, invalidatedResolution])
      expect(await screen.findByText('ready')).toBeVisible()

      act(() => test.getListener()?.('TOKEN_REFRESHED'))

      await waitFor(() => expect(test.cancelQueries).toHaveBeenCalledOnce())
      expect(test.queryClient.getQueryData(['sensitive'])).toBeUndefined()
      expect(await screen.findByText(status)).toBeVisible()
      expect(test.revalidate).toHaveBeenCalledOnce()
    },
  )

  it('blocks state, cancels cache, signs out and navigates in safe order', async () => {
    const test = setup([readyA])
    expect(await screen.findByText('ready')).toBeVisible()

    fireEvent.click(screen.getByRole('button', { name: 'Sign out' }))

    await waitFor(() => expect(test.signOut).toHaveBeenCalledOnce())
    expect(test.events).toEqual(['cancel', 'signOut', 'navigate'])
    expect(test.publishAuthorizationSignal).toHaveBeenCalledWith('signed-out')
    expect(test.queryClient.getQueryData(['sensitive'])).toBeUndefined()
    expect(await screen.findByText('unauthenticated')).toBeVisible()
  })

  it('applies cross-tab SIGNED_OUT cleanup without a custom protocol', async () => {
    const test = setup([readyA])
    expect(await screen.findByText('ready')).toBeVisible()

    act(() => test.getListener()?.('SIGNED_OUT'))

    await waitFor(() => expect(test.navigateToLogin).toHaveBeenCalledOnce())
    expect(test.cancelQueries).toHaveBeenCalledOnce()
    expect(await screen.findByText('unauthenticated')).toBeVisible()
  })
})
