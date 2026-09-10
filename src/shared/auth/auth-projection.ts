export type AuthAccessState =
  | { status: 'anonymous' }
  | { status: 'profile_missing'; userId: string }
  | { status: 'blocked'; userId: string }
  | { status: 'inactive'; userId: string }
  | { status: 'no_access'; userId: string }
  | { status: 'authenticated'; userId: string }

interface AuthProjectionInput {
  userId: string
  appUserStatus: string | null
  membershipStatus: string | null
  tenantAvailable: boolean
  maintenanceEnabled: boolean
}

export function projectAuthAccess({
  userId,
  appUserStatus,
  membershipStatus,
  tenantAvailable,
  maintenanceEnabled,
}: AuthProjectionInput): AuthAccessState {
  if (appUserStatus === null) return { status: 'profile_missing', userId }
  if (appUserStatus === 'blocked') return { status: 'blocked', userId }
  if (appUserStatus !== 'active') return { status: 'inactive', userId }
  if (membershipStatus !== 'active' || !tenantAvailable || !maintenanceEnabled) {
    return { status: 'no_access', userId }
  }
  return { status: 'authenticated', userId }
}

export function normalizeInvitationEmail(email: string): string {
  return email.trim().toLowerCase()
}
