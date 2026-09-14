import { QueryClientProvider, type QueryClient } from '@tanstack/react-query'
import { useEffect, useMemo, useRef, type ReactNode } from 'react'
import { AuthorizationProvider } from '@/app/authorization/authorization-context'
import {
  createAuthorizationSignalBus,
  type AuthorizationSignalBus,
} from '@/app/authorization/authorization-signal'
import { SessionProvider } from '@/app/auth/auth-context'
import {
  RuntimeIdentityContext,
  type RuntimeIdentity,
} from '@/app/providers/runtime-identity'
import type { AuthGateway } from '@/infrastructure/supabase/auth-gateway'
import type { AuthorizationGateway } from '@/infrastructure/supabase/authorization-gateway'
import type { SessionRouterCoordinator } from '@/app/query/session-cache-coordinator'

interface AppProvidersProps extends RuntimeIdentity {
  children: ReactNode
  queryClient: QueryClient
  authGateway: AuthGateway
  authorizationGateway: AuthorizationGateway
  authorizationSignalBus?: AuthorizationSignalBus
  routerCoordinator: SessionRouterCoordinator
}

export function AppProviders({
  children,
  queryClient,
  clientCorrelationId,
  release,
  authGateway,
  authorizationGateway,
  authorizationSignalBus,
  routerCoordinator,
}: AppProvidersProps) {
  const signals = useMemo(
    () => authorizationSignalBus ?? createAuthorizationSignalBus(),
    [authorizationSignalBus],
  )
  const pendingCloseRef = useRef<number | undefined>(undefined)

  useEffect(() => {
    if (pendingCloseRef.current !== undefined) {
      window.clearTimeout(pendingCloseRef.current)
      pendingCloseRef.current = undefined
    }
    return () => {
      if (authorizationSignalBus !== undefined) return
      pendingCloseRef.current = window.setTimeout(() => signals.close(), 0)
    }
  }, [authorizationSignalBus, signals])

  return (
    <RuntimeIdentityContext.Provider value={{ clientCorrelationId, release }}>
      <QueryClientProvider client={queryClient}>
        <SessionProvider
          authorizationSignals={signals}
          gateway={authGateway}
          queryClient={queryClient}
          routerCoordinator={routerCoordinator}
        >
          <AuthorizationProvider
            gateway={authorizationGateway}
            queryClient={queryClient}
            signalBus={signals}
          >
            {children}
          </AuthorizationProvider>
        </SessionProvider>
      </QueryClientProvider>
    </RuntimeIdentityContext.Provider>
  )
}
