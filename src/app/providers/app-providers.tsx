import { QueryClientProvider, type QueryClient } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import {
  RuntimeIdentityContext,
  type RuntimeIdentity,
} from '@/app/providers/runtime-identity'

interface AppProvidersProps extends RuntimeIdentity {
  children: ReactNode
  queryClient: QueryClient
}

export function AppProviders({
  children,
  queryClient,
  clientCorrelationId,
  release,
}: AppProvidersProps) {
  return (
    <RuntimeIdentityContext.Provider value={{ clientCorrelationId, release }}>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </RuntimeIdentityContext.Provider>
  )
}
