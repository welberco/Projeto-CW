import { QueryClientProvider, type QueryClient } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { AuthProvider } from '@/app/auth/auth-context'
import {
  RuntimeIdentityContext,
  type RuntimeIdentity,
} from '@/app/providers/runtime-identity'
import type { AuthGateway } from '@/infrastructure/supabase/auth-gateway'

interface AppProvidersProps extends RuntimeIdentity {
  children: ReactNode
  queryClient: QueryClient
  authGateway: AuthGateway
}

export function AppProviders({
  children,
  queryClient,
  clientCorrelationId,
  release,
  authGateway,
}: AppProvidersProps) {
  return (
    <RuntimeIdentityContext.Provider value={{ clientCorrelationId, release }}>
      <QueryClientProvider client={queryClient}>
        <AuthProvider gateway={authGateway}>{children}</AuthProvider>
      </QueryClientProvider>
    </RuntimeIdentityContext.Provider>
  )
}
