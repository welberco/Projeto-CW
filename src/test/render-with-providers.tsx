import { render, type RenderOptions } from '@testing-library/react'
import type { ReactElement } from 'react'
import { AppProviders } from '@/app/providers/app-providers'
import { createAppQueryClient } from '@/app/query/create-query-client'
import type { ClientCorrelationId } from '@/shared/observability/correlation'
import type { AuthGateway } from '@/infrastructure/supabase/auth-gateway'

const testCorrelationId = 'correlation-test' as ClientCorrelationId

const testAuthGateway: AuthGateway = {
  getAccessState: () => Promise.resolve({ status: 'anonymous' }),
  signIn: () => Promise.resolve({ status: 'anonymous' }),
  signOut: () => Promise.resolve(),
  acceptInvitation: () => Promise.resolve(),
  onAuthChange: () => () => undefined,
}

export function renderWithProviders(
  ui: ReactElement,
  options?: Omit<RenderOptions, 'wrapper'>,
) {
  const queryClient = createAppQueryClient()
  const defaultOptions = queryClient.getDefaultOptions()

  queryClient.setDefaultOptions({
    queries: { ...defaultOptions.queries, retry: false },
    mutations: { ...defaultOptions.mutations, retry: false },
  })

  return {
    queryClient,
    ...render(
      <AppProviders
        authGateway={testAuthGateway}
        clientCorrelationId={testCorrelationId}
        queryClient={queryClient}
        release={{ environment: 'test', releaseId: 'w0b-test' }}
      >
        {ui}
      </AppProviders>,
      options,
    ),
  }
}

export function renderWithAuthGateway(
  ui: ReactElement,
  authGateway: AuthGateway,
) {
  const queryClient = createAppQueryClient()
  queryClient.setDefaultOptions({
    queries: { retry: false },
    mutations: { retry: false },
  })
  return render(
    <AppProviders
      authGateway={authGateway}
      clientCorrelationId={testCorrelationId}
      queryClient={queryClient}
      release={{ environment: 'test', releaseId: 'w1b-test' }}
    >
      {ui}
    </AppProviders>,
  )
}
