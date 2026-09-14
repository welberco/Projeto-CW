import type { ReactNode } from 'react'
import { useAuthorization } from '@/app/authorization/use-authorization'

/** UX-only visibility guard. Backend commands and RLS remain authoritative. */
export function PermissionGuard({
  children,
  fallback = null,
  permissionCode,
  entitlementKey,
}: {
  children: ReactNode
  fallback?: ReactNode
  permissionCode: string
  entitlementKey?: string
}) {
  const { state, hasEntitlement, hasPermission } = useAuthorization()
  const allowed =
    state.status === 'ready' &&
    hasPermission(permissionCode) &&
    (entitlementKey === undefined || hasEntitlement(entitlementKey))

  return allowed ? children : fallback
}
