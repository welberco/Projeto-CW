import { Link } from 'react-router-dom'
import { useAuth } from '@/app/auth/use-auth'
import { useCadastroAccess } from '@/app/pages/cadastros/cadastro-access'
import { CadastroPageHeader } from '@/app/pages/cadastros/cadastro-page-header'
import { cadastroGroups, cadastroRoutes } from '@/app/pages/cadastros/cadastro-routes'
import { NoPermissionPage } from '@/app/pages/no-permission-page'
import { canonicalTenantPath } from '@/app/router/tenant-route'

export function CadastrosIndexPage() {
  const { state } = useAuth()
  const { canVisit, hasEntry } = useCadastroAccess()
  if (state.status !== 'ready' || !hasEntry) return <NoPermissionPage />

  return (
    <div>
      <CadastroPageHeader title="Cadastros" description="Organização dos cadastros estruturais e de manutenção do empreendimento." />
      <div className="grid gap-6 lg:grid-cols-2">
        {cadastroGroups.map((group) => {
          const routes = cadastroRoutes.filter((route) => route.group === group && route.showOnIndex && canVisit(route))
          if (routes.length === 0) return null
          return (
            <section aria-label={group} className="rounded-xl border bg-card p-5" key={group}>
              <h2 className="text-xl font-semibold">{group}</h2>
              <ul className="mt-4 grid gap-2">
                {routes.map((route) => (
                  <li key={route.path}>
                    <Link className="flex min-h-11 items-center rounded-md px-3 text-primary underline-offset-4 hover:bg-muted hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" to={canonicalTenantPath(state.context.tenantRef, route.path)}>
                      {route.title}
                    </Link>
                  </li>
                ))}
              </ul>
            </section>
          )
        })}
      </div>
    </div>
  )
}
