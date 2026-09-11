import { describe, expect, it } from 'vitest'
import {
  contextIdentityChanged,
  parseTenantRef,
  projectTenantContextRow,
  transitionSessionState,
  type SessionState,
  type TenantContextResolution,
} from '@/shared/session/tenant-context'

const readyResolution: TenantContextResolution = {
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

describe('tenant context state machine', () => {
  it('accepts only UUID v4 tenant route selectors', () => {
    expect(parseTenantRef(' 34000000-0000-4000-8000-000000000001 ')).toBe(
      '34000000-0000-4000-8000-000000000001',
    )
    expect(parseTenantRef('opaque-ref_123')).toBeNull()
    expect(parseTenantRef('34000000-0000-1000-8000-000000000001')).toBeNull()
  })

  it.each([
    'profile_missing',
    'principal_unavailable',
    'no_membership',
    'membership_unavailable',
    'tenant_unavailable',
    'feature_unavailable',
    'tenant_context_unavailable',
  ] as const)('projects the safe %s resolver state', (status) => {
    expect(
      projectTenantContextRow({
        context_status: status,
        principal_id: 'principal-a',
        tenant_id: null,
        tenant_ref: null,
        tenant_display_name: null,
        membership_id: null,
        membership_version: null,
      }),
    ).toEqual({ status, principalId: 'principal-a' })
  })

  it('rejects partial ready projections', () => {
    expect(() =>
      projectTenantContextRow({
        context_status: 'ready',
        principal_id: 'principal-a',
        tenant_id: null,
        tenant_ref: null,
        tenant_display_name: null,
        membership_id: null,
        membership_version: null,
      }),
    ).toThrow('Invalid authoritative tenant-context projection.')
  })

  it('keeps generation on token refresh for the same persisted context', () => {
    const initial = transitionSessionState(
      { status: 'booting' },
      readyResolution,
      1,
    )
    const refreshed = transitionSessionState(initial, readyResolution, 2)

    expect(refreshed.status).toBe('ready')
    if (refreshed.status === 'ready') {
      expect(refreshed.context.contextGeneration).toBe(1)
    }
    expect(contextIdentityChanged(initial, refreshed)).toBe(false)
  })

  it('creates a new generation and cache boundary when principal changes', () => {
    const previous = transitionSessionState(
      { status: 'booting' },
      readyResolution,
      1,
    )
    const next = transitionSessionState(
      previous,
      {
        ...readyResolution,
        context: { ...readyResolution.context, principalId: 'principal-b' },
      },
      2,
    )

    expect(contextIdentityChanged(previous, next)).toBe(true)
    if (next.status === 'ready') {
      expect(next.context.contextGeneration).toBe(2)
    }
  })

  it('creates a cache boundary when an authorized context becomes unavailable', () => {
    const previous = transitionSessionState(
      { status: 'booting' },
      readyResolution,
      1,
    )
    const next: SessionState = {
      status: 'membership_unavailable',
      principalId: 'principal-a',
    }
    expect(contextIdentityChanged(previous, next)).toBe(true)
  })
})
