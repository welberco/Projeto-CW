import { parseTenantRef } from '@/shared/session/tenant-context'
import { cadastroRoutes } from '@/app/pages/cadastros/cadastro-routes'

const navigableDestinations = new Set([
  'dashboard',
  'minha-conta',
  'cadastros',
  ...cadastroRoutes.filter((route) => !route.path.includes(':')).map((route) => route.path),
])

const uuidSegment = '[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
const dynamicDestinations = cadastroRoutes
  .filter((route) => route.path.includes(':'))
  .map((route) => new RegExp(`^${route.path.replace(/:[^/]+/g, uuidSegment)}$`, 'i'))

function isNavigableDestination(destination: string) {
  return navigableDestinations.has(destination) || dynamicDestinations.some((pattern) => pattern.test(destination))
}

export function canonicalTenantPath(
  tenantRef: string,
  destination: string = 'dashboard',
): string {
  const normalizedTenantRef = parseTenantRef(tenantRef)
  if (normalizedTenantRef === null || !isNavigableDestination(destination)) {
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
