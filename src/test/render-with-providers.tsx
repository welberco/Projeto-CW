import { render, type RenderOptions } from '@testing-library/react'
import type { ReactElement } from 'react'
import { AppProviders } from '@/app/providers/app-providers'
import { createAppQueryClient } from '@/app/query/create-query-client'
import type { ClientCorrelationId } from '@/shared/observability/correlation'

const testCorrelationId = 'correlation-test' as ClientCorrelationId

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
