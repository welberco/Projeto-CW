export const authorizationScopes = [
  'OWN',
  'ASSIGNED',
  'TEAM',
  'ALL_TENANT',
] as const

export type AuthorizationScope = (typeof authorizationScopes)[number]

export interface AuthorizationRevisionVector {
  membershipVersion: number
  profileVersion: number
  catalogRevision: number
}

export interface AuthorizationProjection {
  principalId: string
  tenantId: string
  tenantRef: string
  membershipId: string
  profileId: string
  profileName: string
  revision: AuthorizationRevisionVector
  authorizationRevision: string
  permissionCodes: readonly string[]
  enabledEntitlements: readonly string[]
}

export type AuthorizationUnavailableStatus =
  | 'principal_unavailable'
  | 'no_membership'
  | 'membership_unavailable'
  | 'tenant_unavailable'
  | 'profile_unavailable'
  | 'authorization_unavailable'

export type AuthorizationProjectionResolution =
  | { status: 'unauthenticated' }
  | { status: AuthorizationUnavailableStatus; principalId: string }
  | { status: 'ready'; projection: AuthorizationProjection }

export interface AuthorizationProjectionRow {
  projection_status: string
  principal_id: string | null
  tenant_id: string | null
  tenant_ref: string | null
  membership_id: string | null
  membership_version: number | null
  profile_id: string | null
  profile_version: number | null
  profile_name: string | null
  catalog_revision: number | null
  authorization_revision: string | null
  permission_codes: string[] | null
  enabled_entitlements: string[] | null
}

const unavailableStatuses = new Set<AuthorizationUnavailableStatus>([
  'principal_unavailable',
  'no_membership',
  'membership_unavailable',
  'tenant_unavailable',
  'profile_unavailable',
  'authorization_unavailable',
])

const permissionCodePattern =
  /^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\.(own|assigned|team|all_tenant)$/
const entitlementPattern = /^[a-z][a-z0-9_]*$/

export function serializeAuthorizationRevision(
  revision: AuthorizationRevisionVector,
): string {
  return `m${revision.membershipVersion}:p${revision.profileVersion}:c${revision.catalogRevision}`
}

function isPositiveInteger(value: number): boolean {
  return Number.isSafeInteger(value) && value > 0
}

function isSortedUnique(values: readonly string[]): boolean {
  return values.every(
    (value, index) => index === 0 || (values[index - 1] ?? '') < value,
  )
}

export function projectAuthorizationRow(
  row: AuthorizationProjectionRow,
): AuthorizationProjectionResolution {
  if (row.projection_status === 'unauthenticated') {
    return { status: 'unauthenticated' }
  }

  if (
    unavailableStatuses.has(
      row.projection_status as AuthorizationUnavailableStatus,
    ) &&
    row.principal_id !== null
  ) {
    return {
      status: row.projection_status as AuthorizationUnavailableStatus,
      principalId: row.principal_id,
    }
  }

  if (
    row.projection_status !== 'ready' ||
    row.principal_id === null ||
    row.tenant_id === null ||
    row.tenant_ref === null ||
    row.membership_id === null ||
    row.membership_version === null ||
    row.profile_id === null ||
    row.profile_version === null ||
    row.profile_name === null ||
    row.catalog_revision === null ||
    row.authorization_revision === null ||
    row.permission_codes === null ||
    row.enabled_entitlements === null
  ) {
    throw new Error('Invalid authoritative authorization projection.')
  }

  const revision = {
    membershipVersion: row.membership_version,
    profileVersion: row.profile_version,
    catalogRevision: row.catalog_revision,
  }

  if (
    !isPositiveInteger(revision.membershipVersion) ||
    !isPositiveInteger(revision.profileVersion) ||
    !isPositiveInteger(revision.catalogRevision) ||
    row.authorization_revision !== serializeAuthorizationRevision(revision) ||
    row.profile_name.trim() !== row.profile_name ||
    row.profile_name.length === 0 ||
    !row.permission_codes.every((code) => permissionCodePattern.test(code)) ||
    !row.enabled_entitlements.every((key) => entitlementPattern.test(key)) ||
    !isSortedUnique(row.permission_codes) ||
    !isSortedUnique(row.enabled_entitlements)
  ) {
    throw new Error('Invalid authoritative authorization projection.')
  }

  return {
    status: 'ready',
    projection: {
      principalId: row.principal_id,
      tenantId: row.tenant_id,
      tenantRef: row.tenant_ref,
      membershipId: row.membership_id,
      profileId: row.profile_id,
      profileName: row.profile_name,
      revision,
      authorizationRevision: row.authorization_revision,
      permissionCodes: Object.freeze([...row.permission_codes]),
      enabledEntitlements: Object.freeze([...row.enabled_entitlements]),
    },
  }
}

export function authorizationProjectionSemanticKey(
  projection: AuthorizationProjection,
): string {
  return [
    projection.principalId,
    projection.tenantId,
    projection.membershipId,
    projection.profileId,
    projection.authorizationRevision,
    projection.permissionCodes.join(','),
    projection.enabledEntitlements.join(','),
  ].join('|')
}

export function hasProjectedPermission(
  projection: AuthorizationProjection,
  permissionCode: string,
): boolean {
  return permissionCodePattern.test(permissionCode)
    ? projection.permissionCodes.includes(permissionCode)
    : false
}

export function hasProjectedEntitlement(
  projection: AuthorizationProjection,
  entitlementKey: string,
): boolean {
  return entitlementPattern.test(entitlementKey)
    ? projection.enabledEntitlements.includes(entitlementKey)
    : false
}
