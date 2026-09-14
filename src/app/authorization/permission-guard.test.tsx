import { render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { PermissionGuard } from '@/app/authorization/permission-guard'
import {
  AuthorizationContext,
  type AuthorizationContextValue,
} from '@/app/authorization/use-authorization'
import type { AuthorizationProjection } from '@/shared/authorization/authorization-projection'

const projection: AuthorizationProjection = {
  principalId: 'principal-a',
  tenantId: 'tenant-a',
  tenantRef: '34000000-0000-4000-8000-000000000001',
  membershipId: 'membership-a',
  profileId: 'profile-a',
  profileName: 'Gestor',
  revision: { membershipVersion: 1, profileVersion: 1, catalogRevision: 12 },
  authorizationRevision: 'm1:p1:c12',
  permissionCodes: ['core.users.read.all_tenant'],
  enabledEntitlements: ['maintenance'],
}

function renderGuard(value: AuthorizationContextValue, entitlementKey?: string) {
  render(
    <AuthorizationContext.Provider value={value}>
      <PermissionGuard
        permissionCode="core.users.read.all_tenant"
        {...(entitlementKey === undefined ? {} : { entitlementKey })}
        fallback={<span>blocked</span>}
      >
        <span>allowed</span>
      </PermissionGuard>
    </AuthorizationContext.Provider>,
  )
}

function contextValue(
  state: AuthorizationContextValue['state'],
): AuthorizationContextValue {
  return {
    state,
    refreshAuthorization: vi.fn(() => Promise.resolve()),
    invalidateAuthorization: vi.fn(() => Promise.resolve()),
    hasPermission: (code) =>
      state.status === 'ready' && state.projection.permissionCodes.includes(code),
    hasEntitlement: (key) =>
      state.status === 'ready' && state.projection.enabledEntitlements.includes(key),
  }
}

describe('permission guard', () => {
  it('renders children only for an exact permission and enabled entitlement', () => {
    renderGuard(
      contextValue({ status: 'ready', projection, authorizationGeneration: 1 }),
      'maintenance',
    )
    expect(screen.getByText('allowed')).toBeVisible()
  })

  it.each([
    { status: 'loading' } as const,
    { status: 'refreshing' } as const,
    { status: 'unauthenticated' } as const,
    { status: 'unavailable', reason: 'network' } as const,
    {
      status: 'ready',
      projection: { ...projection, permissionCodes: [] },
      authorizationGeneration: 1,
    } as const,
  ])('fails closed for state $status', (state) => {
    renderGuard(contextValue(state), 'maintenance')
    expect(screen.getByText('blocked')).toBeVisible()
  })

  it('fails closed when the entitlement is disabled', () => {
    renderGuard(
      contextValue({
        status: 'ready',
        projection: { ...projection, enabledEntitlements: [] },
        authorizationGeneration: 1,
      }),
      'maintenance',
    )
    expect(screen.getByText('blocked')).toBeVisible()
  })
})
