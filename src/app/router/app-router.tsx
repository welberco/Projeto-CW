import {
  createBrowserRouter,
  createMemoryRouter,
  Outlet,
  type RouteObject,
} from 'react-router-dom'
import { AppShell } from '@/app/layout/app-shell'
import { LoadingRouteState } from '@/app/pages/loading-route-state'
import { NotFoundPage } from '@/app/pages/not-found-page'
import { PlatformBoundaryPage } from '@/app/pages/platform-boundary-page'
import { RouteErrorPage } from '@/app/pages/route-error-page'
import { TechnicalHomePage } from '@/app/pages/technical-home-page'
import { TenantBoundaryPage } from '@/app/pages/tenant-boundary-page'

export const appRoutes = [
  {
    path: '/',
    element: <AppShell />,
    errorElement: <RouteErrorPage />,
    HydrateFallback: LoadingRouteState,
    children: [
      { index: true, element: <TechnicalHomePage /> },
      {
        path: 'e/:tenantRef',
        element: <Outlet />,
        children: [
          { index: true, element: <TenantBoundaryPage /> },
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
