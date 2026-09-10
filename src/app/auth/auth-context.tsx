import { useEffect, useMemo, useState, type ReactNode } from 'react'
import {
  AuthContext,
  type AuthContextValue,
  type AuthViewState,
} from '@/app/auth/use-auth'
import type { AuthGateway } from '@/infrastructure/supabase/auth-gateway'

export function AuthProvider({
  children,
  gateway,
}: {
  children: ReactNode
  gateway: AuthGateway
}) {
  const [state, setState] = useState<AuthViewState>({ status: 'loading' })

  useEffect(() => {
    let active = true
    const refresh = () => {
      void gateway
        .getAccessState()
        .then((nextState) => active && setState(nextState))
        .catch(() => active && setState({ status: 'error' }))
    }
    refresh()
    const unsubscribe = gateway.onAuthChange(refresh)
    return () => {
      active = false
      unsubscribe()
    }
  }, [gateway])

  const value = useMemo<AuthContextValue>(
    () => ({
      state,
      async signIn(email, password) {
        setState({ status: 'loading' })
        try {
          setState(await gateway.signIn(email, password))
        } catch (error) {
          setState({ status: 'anonymous' })
          throw error
        }
      },
      async signOut() {
        try {
          await gateway.signOut()
          setState({ status: 'anonymous' })
        } catch {
          setState({ status: 'error' })
        }
      },
      acceptInvitation: (token, correlationId) =>
        gateway.acceptInvitation(token, correlationId),
    }),
    [gateway, state],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
