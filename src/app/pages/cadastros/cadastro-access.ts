import { useAuthorization } from '@/app/authorization/use-authorization'
import { cadastroRoutes, type CadastroRouteDefinition } from '@/app/pages/cadastros/cadastro-routes'

export function useCadastroAccess() {
  const { state, hasEntitlement, hasPermission } = useAuthorization()

  const canVisit = (route: CadastroRouteDefinition) =>
    state.status === 'ready' &&
    route.permissionCodes.some((code) => hasPermission(code)) &&
    (route.entitlementKey === undefined || hasEntitlement(route.entitlementKey))

  return {
    canVisit,
    hasEntry: cadastroRoutes.some((route) => route.showOnIndex && canVisit(route)),
  }
}
