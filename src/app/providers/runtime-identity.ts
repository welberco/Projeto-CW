import { createContext, useContext } from 'react'
import type { ClientCorrelationId } from '@/shared/observability/correlation'
import type { ReleaseIdentity } from '@/shared/observability/release'

export interface RuntimeIdentity {
  clientCorrelationId: ClientCorrelationId
  release: ReleaseIdentity
}

export const RuntimeIdentityContext = createContext<RuntimeIdentity | null>(null)

export function useRuntimeIdentity(): RuntimeIdentity {
  const identity = useContext(RuntimeIdentityContext)

  if (identity === null) {
    throw new Error('Runtime identity provider is missing.')
  }

  return identity
}
