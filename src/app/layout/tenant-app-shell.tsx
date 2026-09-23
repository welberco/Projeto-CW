import type { ReactNode } from 'react'
import { Link, NavLink, useLocation } from 'react-router-dom'
import { useCadastroAccess } from '@/app/pages/cadastros/cadastro-access'
import { canonicalTenantPath } from '@/app/router/tenant-route'
import type { AuthorizedTenantContext } from '@/shared/session/tenant-context'
import { cn } from '@/shared/lib/cn'

export function TenantAppShell({
  children,
  context,
  onSignOut,
}: {
  children: ReactNode
  context: AuthorizedTenantContext
  onSignOut: () => Promise<void>
}) {
  const { hasEntry } = useCadastroAccess()
  const location = useLocation()
  const currentPath = location.pathname.toLowerCase()
  const tenantPrefix = `/e/${context.tenantRef.toLowerCase()}/`
  const cadastrosActive = currentPath === `${tenantPrefix}cadastros`
    || currentPath.startsWith(`${tenantPrefix}cadastros/`)
    || currentPath.startsWith(`${tenantPrefix}manutencao/`)
  const navigation = [
    {
      label: 'Visão Geral',
      to: canonicalTenantPath(context.tenantRef, 'dashboard'),
    },
    {
      label: 'Minha Conta',
      to: canonicalTenantPath(context.tenantRef, 'minha-conta'),
    },
  ]

  return (
    <div className="mx-auto flex min-h-[calc(100vh-4rem)] w-full max-w-7xl flex-col">
      <header className="border-b border-border bg-card px-4 py-4 sm:px-6">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div>
            <p className="font-semibold tracking-tight">CW ERP</p>
            <p className="text-sm text-muted-foreground">
              {context.tenantDisplayName}
            </p>
          </div>
          <button
            className="min-h-11 rounded-md px-3 text-sm font-semibold text-muted-foreground hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            onClick={() => void onSignOut()}
            type="button"
          >
            Sair
          </button>
        </div>
      </header>

      <div className="grid flex-1 md:grid-cols-[13rem_minmax(0,1fr)]">
        <nav
          aria-label="Navegação principal"
          className="border-b border-border bg-card px-4 py-3 md:border-b-0 md:border-r md:px-4 md:py-6"
        >
          <ul className="flex flex-wrap gap-2 md:flex-col">
            {navigation.map((item) => (
              <li key={item.to}>
                <NavLink
                  className={({ isActive }) =>
                    cn(
                      'flex min-h-11 items-center rounded-md px-3 text-sm font-medium text-muted-foreground hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                      isActive && 'bg-muted text-foreground',
                    )
                  }
                  to={item.to}
                >
                  {item.label}
                </NavLink>
              </li>
            ))}
            {hasEntry ? (
              <li>
                <Link
                  aria-current={cadastrosActive ? 'page' : undefined}
                  className={cn(
                    'flex min-h-11 items-center rounded-md px-3 text-sm font-medium text-muted-foreground hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                    cadastrosActive && 'bg-muted text-foreground',
                  )}
                  to={canonicalTenantPath(context.tenantRef, 'cadastros')}
                >
                  Cadastros
                </Link>
              </li>
            ) : null}
          </ul>
        </nav>

        <main className="min-w-0 px-4 py-8 sm:px-6">
          {children}
        </main>
      </div>
    </div>
  )
}
