import { QueryClientProvider, type QueryClient } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { SessionProvider } from '@/app/auth/auth-context'
import {
  RuntimeIdentityContext,
  type RuntimeIdentity,
} from '@/app/providers/runtime-identity'
import type { AuthGateway } from '@/infrastructure/supabase/auth-gateway'
import type { SessionRouterCoordinator } from '@/app/query/session-cache-coordinator'

interface AppProvidersProps extends RuntimeIdentity {
  children: ReactNode
  queryClient: QueryClient
  authGateway: AuthGateway
  routerCoordinator: SessionRouterCoordinator
}

export function AppProviders({
  children,
  queryClient,
  clientCorrelationId,
  release,
  authGateway,
  routerCoordinator,
}: AppProvidersProps) {
  return (
    <RuntimeIdentityContext.Provider value={{ clientCorrelationId, release }}>
      <QueryClientProvider client={queryClient}>
        <SessionProvider
          gateway={authGateway}
          queryClient={queryClient}
          routerCoordinator={routerCoordinator}
        >
          {children}
        </SessionProvider>
      </QueryClientProvider>
    </RuntimeIdentityContext.Provider>
  )
}
