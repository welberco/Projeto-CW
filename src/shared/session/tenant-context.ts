export interface ContextIdentity {
  principalId: string
  tenantId: string
  membershipId: string
  membershipVersion: number
  contextGeneration: number
}

export interface AuthorizedTenantContext extends ContextIdentity {
  tenantRef: string
  tenantDisplayName: string
}

export type TenantContextUnavailableStatus =
  | 'profile_missing'
  | 'principal_unavailable'
  | 'no_membership'
  | 'membership_unavailable'
  | 'tenant_unavailable'
  | 'feature_unavailable'
  | 'tenant_context_unavailable'

export type TenantContextResolution =
  | { status: 'unauthenticated' }
  | { status: TenantContextUnavailableStatus; principalId: string }
  | {
      status: 'ready'
      context: Omit<AuthorizedTenantContext, 'contextGeneration'>
    }

export type SessionState =
  | { status: 'booting' }
  | { status: 'error' }
  | { status: 'unauthenticated' }
  | { status: TenantContextUnavailableStatus; principalId: string }
  | { status: 'ready'; context: AuthorizedTenantContext }

export interface TenantContextRow {
  context_status: string
  principal_id: string | null
  tenant_id: string | null
  tenant_ref: string | null
  tenant_display_name: string | null
  membership_id: string | null
  membership_version: number | null
}

const unavailableStatuses = new Set<TenantContextUnavailableStatus>([
  'profile_missing',
  'principal_unavailable',
  'no_membership',
  'membership_unavailable',
  'tenant_unavailable',
  'feature_unavailable',
  'tenant_context_unavailable',
])

export function parseTenantRef(value: string): string | null {
  const normalized = value.trim().toLowerCase()
  return /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(
    normalized,
  )
    ? normalized
    : null
}

export function projectTenantContextRow(
  row: TenantContextRow,
): TenantContextResolution {
  if (row.context_status === 'unauthenticated') {
    return { status: 'unauthenticated' }
  }

  if (
    unavailableStatuses.has(
      row.context_status as TenantContextUnavailableStatus,
    ) &&
    row.principal_id !== null
  ) {
    return {
      status: row.context_status as TenantContextUnavailableStatus,
      principalId: row.principal_id,
    }
  }

  if (
    row.context_status === 'ready' &&
    row.principal_id !== null &&
    row.tenant_id !== null &&
    row.tenant_ref !== null &&
    row.tenant_display_name !== null &&
    row.membership_id !== null &&
    row.membership_version !== null
  ) {
    return {
      status: 'ready',
      context: {
        principalId: row.principal_id,
        tenantId: row.tenant_id,
        tenantRef: row.tenant_ref,
        tenantDisplayName: row.tenant_display_name,
        membershipId: row.membership_id,
        membershipVersion: row.membership_version,
      },
    }
  }

  throw new Error('Invalid authoritative tenant-context projection.')
}

function isSameContext(
  current: AuthorizedTenantContext,
  next: Omit<AuthorizedTenantContext, 'contextGeneration'>,
) {
  return (
    current.principalId === next.principalId &&
    current.tenantId === next.tenantId &&
    current.membershipId === next.membershipId &&
    current.membershipVersion === next.membershipVersion
  )
}

export function transitionSessionState(
  current: SessionState,
  resolution: TenantContextResolution,
  nextGeneration: number,
): SessionState {
  if (resolution.status !== 'ready') return resolution

  const contextGeneration =
    current.status === 'ready' &&
    isSameContext(current.context, resolution.context)
      ? current.context.contextGeneration
      : nextGeneration

  return {
    status: 'ready',
    context: { ...resolution.context, contextGeneration },
  }
}

export function contextIdentityChanged(
  previous: SessionState,
  next: SessionState,
): boolean {
  if (previous.status !== 'ready') return false
  if (next.status !== 'ready') return true
  return previous.context.contextGeneration !== next.context.contextGeneration
}
