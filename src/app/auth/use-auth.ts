import { createContext, useContext } from 'react'
import type { SessionState } from '@/shared/session/tenant-context'

export interface AuthContextValue {
  state: SessionState
  signIn: (email: string, password: string) => Promise<void>
  signOut: () => Promise<void>
  acceptInvitation: (token: string, correlationId: string) => Promise<void>
  resolveTenantRef: (tenantRef: string) => Promise<void>
  refreshSession: () => Promise<void>
}

export const AuthContext = createContext<AuthContextValue | null>(null)

export function useAuth(): AuthContextValue {
  const value = useContext(AuthContext)
  if (value === null) throw new Error('SessionProvider is missing.')
  return value
}
