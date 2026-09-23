import { parseTenantRef } from '@/shared/session/tenant-context'
import { cadastroRoutes } from '@/app/pages/cadastros/cadastro-routes'

const navigableDestinations = new Set([
  'dashboard',
  'minha-conta',
  'cadastros',
  ...cadastroRoutes.filter((route) => !route.path.includes(':')).map((route) => route.path),
])

export function canonicalTenantPath(
  tenantRef: string,
  destination: string = 'dashboard',
): string {
  const normalizedTenantRef = parseTenantRef(tenantRef)
  if (normalizedTenantRef === null || !navigableDestinations.has(destination)) {
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
