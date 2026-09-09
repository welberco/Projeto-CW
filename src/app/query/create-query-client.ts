import { QueryClient } from '@tanstack/react-query'
import { AppError } from '@/shared/errors/app-error'

const nonRetryableCategories = new Set([
  'validation',
  'unauthenticated',
  'forbidden',
  'not_found',
  'conflict',
  'invalid_state',
  'limit',
])

export function createAppQueryClient(): QueryClient {
  return new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: 30_000,
        gcTime: 5 * 60_000,
        refetchOnWindowFocus: true,
        retry: (failureCount, error) => {
          if (
            error instanceof AppError &&
            nonRetryableCategories.has(error.category)
          ) {
            return false
          }

          return failureCount < 2
        },
      },
      mutations: {
        retry: false,
      },
    },
  })
}
