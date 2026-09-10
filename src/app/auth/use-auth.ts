import { createContext, useContext } from 'react'
import type { AuthAccessState } from '@/shared/auth/auth-projection'

export type AuthViewState =
  | AuthAccessState
  | { status: 'loading' }
  | { status: 'error' }

export interface AuthContextValue {
  state: AuthViewState
  signIn: (email: string, password: string) => Promise<void>
  signOut: () => Promise<void>
  acceptInvitation: (token: string, correlationId: string) => Promise<void>
}

export const AuthContext = createContext<AuthContextValue | null>(null)

export function useAuth(): AuthContextValue {
  const value = useContext(AuthContext)
  if (value === null) throw new Error('AuthProvider is missing.')
  return value
}
