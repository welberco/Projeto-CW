import { Link, useParams } from 'react-router-dom'
import { useAuth } from '@/app/auth/use-auth'
import { useCadastroAccess } from '@/app/pages/cadastros/cadastro-access'
import { CadastroPageHeader } from '@/app/pages/cadastros/cadastro-page-header'
import type { CadastroRouteDefinition } from '@/app/pages/cadastros/cadastro-routes'
import { NoPermissionPage } from '@/app/pages/no-permission-page'
import { NotFoundPage } from '@/app/pages/not-found-page'
import { canonicalTenantPath } from '@/app/router/tenant-route'
import { StatePanel } from '@/shared/ui/state-panel'

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

export function CadastroRoutePage({ route }: { route: CadastroRouteDefinition }) {
  const params = useParams()
  const { state } = useAuth()
  const { canVisit } = useCadastroAccess()

  if (!canVisit(route)) return <NoPermissionPage />
  if (route.idParam !== undefined && Object.entries(params).some(([name, value]) => name !== 'tenantRef' && (value === undefined || !uuidPattern.test(value)))) {
    return <NotFoundPage />
  }
  if (state.status !== 'ready') return <NoPermissionPage />

  return (
    <section aria-label={route.title}>
      <CadastroPageHeader title={route.title} description="Esta área será disponibilizada nas próximas etapas da W4D. Nenhuma consulta ou alteração de cadastro está ativa nesta página." />
      <StatePanel title="Funcionalidade em preparação" description="A rota já está disponível para navegação. A gestão deste cadastro ainda não foi habilitada." headingLevel={2} />
      <Link className="mt-5 inline-flex min-h-11 items-center rounded-md text-primary underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" to={canonicalTenantPath(state.context.tenantRef, 'cadastros')}>
        Voltar a Cadastros
      </Link>
    </section>
  )
}
