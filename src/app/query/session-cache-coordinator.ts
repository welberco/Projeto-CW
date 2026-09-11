import type { QueryClient } from '@tanstack/react-query'

export interface SessionRouterCoordinator {
  navigateToLogin: () => void | Promise<void>
  revalidate: () => void
}

export async function clearSessionCache(queryClient: QueryClient) {
  await queryClient.cancelQueries()
  queryClient.clear()
}
