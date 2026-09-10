import { QueryClient } from '@tanstack/react-query'
import { render, type RenderOptions } from '@testing-library/react'
import type { ReactElement } from 'react'
import { AppProviders } from '@/app/providers/app-providers'
import type { ClientCorrelationId } from '@/shared/observability/correlation'

const testCorrelationId = 'correlation-test' as ClientCorrelationId

export function renderWithProviders(
  ui: ReactElement,
  options?: Omit<RenderOptions, 'wrapper'>,
) {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: { retry: false },
      mutations: { retry: false },
    },
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
