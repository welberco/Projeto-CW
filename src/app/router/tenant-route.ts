import { parseTenantRef } from '@/shared/session/tenant-context'

export type TenantDestination = 'dashboard' | 'minha-conta'

export function canonicalTenantPath(
  tenantRef: string,
  destination: TenantDestination = 'dashboard',
): string {
  const normalizedTenantRef = parseTenantRef(tenantRef)
  if (normalizedTenantRef === null) {
    throw new Error('Cannot build a tenant route from an invalid reference.')
  }

  return `/e/${normalizedTenantRef}/${destination}`
}

export function tenantRouteMatches(
  routeTenantRef: string | undefined,
  authoritativeTenantRef: string,
): boolean {
  if (routeTenantRef === undefined) return false
  return parseTenantRef(routeTenantRef) === authoritativeTenantRef.toLowerCase()
}
