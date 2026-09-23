import { createBrowserRouter, createMemoryRouter, Outlet, type RouteObject } from 'react-router-dom'
import { AppShell } from '@/app/layout/app-shell'
import { HomeRoutePage } from '@/app/pages/home-route-page'
import { LoadingRouteState } from '@/app/pages/loading-route-state'
import { MyAccountPage } from '@/app/pages/my-account-page'
import { NotFoundPage } from '@/app/pages/not-found-page'
import { PlatformBoundaryPage } from '@/app/pages/platform-boundary-page'
import { RouteErrorPage } from '@/app/pages/route-error-page'
import { TenantDashboardPage } from '@/app/pages/tenant-dashboard-page'
import { TenantIndexPage } from '@/app/pages/tenant-index-page'
import { InvitationPage } from '@/app/pages/invitation-page'
import { LoginPage } from '@/app/pages/login-page'
import { TenantRouteBoundary } from '@/app/router/tenant-route-boundary'
import { CadastrosIndexPage } from '@/app/pages/cadastros/cadastros-index-page'
import { CadastroRoutePage } from '@/app/pages/cadastros/cadastro-route-page'
import { cadastroRoutes } from '@/app/pages/cadastros/cadastro-routes'

export const appRoutes = [
  {
    path: '/',
    element: <AppShell />,
    errorElement: <RouteErrorPage />,
    HydrateFallback: LoadingRouteState,
    children: [
      { index: true, element: <HomeRoutePage /> },
      { path: 'login', element: <LoginPage /> },
      { path: 'convite', element: <InvitationPage /> },
      {
        path: 'e/:tenantRef',
        element: <TenantRouteBoundary />,
        children: [
          { index: true, element: <TenantIndexPage /> },
          { path: 'dashboard', element: <TenantDashboardPage /> },
          { path: 'minha-conta', element: <MyAccountPage /> },
          { path: 'cadastros', element: <CadastrosIndexPage /> },
          ...cadastroRoutes.map((route) => ({
            path: route.path,
            element: <CadastroRoutePage route={route} />,
          })),
          { path: '*', element: <NotFoundPage /> },
        ],
      },
      {
        path: 'plataforma',
        element: <Outlet />,
        children: [
          { index: true, element: <PlatformBoundaryPage /> },
          { path: '*', element: <NotFoundPage /> },
        ],
      },
      { path: '*', element: <NotFoundPage /> },
    ],
  },
] satisfies RouteObject[]

export function createAppRouter() {
  return createBrowserRouter(appRoutes)
}

export function createAppMemoryRouter(initialEntries: string[]) {
  return createMemoryRouter(appRoutes, { initialEntries })
}
