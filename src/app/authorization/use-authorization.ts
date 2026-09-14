import { createContext, useContext } from 'react'
import type {
  AuthorizationProjection,
  AuthorizationUnavailableStatus,
} from '@/shared/authorization/authorization-projection'

export type AuthorizationState =
  | { status: 'idle' }
  | { status: 'loading' | 'refreshing' }
  | { status: 'unauthenticated' }
  | { status: 'unavailable'; reason: AuthorizationUnavailableStatus | 'context_mismatch' | 'network' }
  | {
      status: 'ready'
      projection: AuthorizationProjection
      authorizationGeneration: number
    }

export interface AuthorizationContextValue {
  state: AuthorizationState
  refreshAuthorization: () => Promise<void>
  invalidateAuthorization: () => Promise<void>
  hasPermission: (permissionCode: string) => boolean
  hasEntitlement: (entitlementKey: string) => boolean
}

export const AuthorizationContext =
  createContext<AuthorizationContextValue | null>(null)

export function useAuthorization(): AuthorizationContextValue {
  const value = useContext(AuthorizationContext)
  if (value === null) throw new Error('AuthorizationProvider is missing.')
  return value
}
