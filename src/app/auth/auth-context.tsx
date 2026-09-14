import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import type { QueryClient } from '@tanstack/react-query'
import {
  AuthContext,
  type AuthContextValue,
} from '@/app/auth/use-auth'
import {
  clearSessionCache,
  type SessionRouterCoordinator,
} from '@/app/query/session-cache-coordinator'
import type { AuthGateway } from '@/infrastructure/supabase/auth-gateway'
import type { AuthorizationSignalBus } from '@/app/authorization/authorization-signal'
import {
  contextIdentityChanged,
  transitionSessionState,
  type SessionState,
} from '@/shared/session/tenant-context'

export function SessionProvider({
  children,
  gateway,
  queryClient,
  routerCoordinator,
  authorizationSignals,
}: {
  children: ReactNode
  gateway: AuthGateway
  queryClient: QueryClient
  routerCoordinator: SessionRouterCoordinator
  authorizationSignals?: AuthorizationSignalBus
}) {
  const [state, setState] = useState<SessionState>({ status: 'booting' })
  const currentStateRef = useRef<SessionState>({ status: 'booting' })
  const contextGenerationRef = useRef(0)
  const requestGenerationRef = useRef(0)

  const replaceState = useCallback((nextState: SessionState) => {
    currentStateRef.current = nextState
    setState(nextState)
  }, [])

  const refresh = useCallback(
    async (targetTenantRef?: string | null) => {
      const requestGeneration = ++requestGenerationRef.current
      const previousState = currentStateRef.current
      setState({ status: 'booting' })

      try {
        const resolution = await gateway.resolveSession(targetTenantRef)
        if (requestGeneration !== requestGenerationRef.current) return

        const nextState = transitionSessionState(
          previousState,
          resolution,
          contextGenerationRef.current + 1,
        )

        if (contextIdentityChanged(previousState, nextState)) {
          await clearSessionCache(queryClient)
        }

        if (nextState.status === 'ready') {
          contextGenerationRef.current = nextState.context.contextGeneration
        }
        replaceState(nextState)
      } catch {
        if (requestGeneration !== requestGenerationRef.current) return
        await clearSessionCache(queryClient)
        replaceState({ status: 'error' })
      }
    },
    [gateway, queryClient, replaceState],
  )

  const handleSignedOut = useCallback(async () => {
    ++requestGenerationRef.current
    replaceState({ status: 'booting' })
    await clearSessionCache(queryClient)
    replaceState({ status: 'unauthenticated' })
    await routerCoordinator.navigateToLogin()
  }, [queryClient, replaceState, routerCoordinator])

  useEffect(() => {
    let active = true
    const refreshIfActive = () => {
      if (active) void refresh()
    }
    refreshIfActive()
    const unsubscribe = gateway.onAuthChange((event) => {
      if (!active) return
      if (event === 'SIGNED_OUT') {
        void handleSignedOut()
        return
      }
      void refresh().then(() => routerCoordinator.revalidate())
    })
    const revalidateOnFocus = () => {
      if (!document.hidden) refreshIfActive()
    }
    window.addEventListener('focus', revalidateOnFocus)
    return () => {
      active = false
      unsubscribe()
      window.removeEventListener('focus', revalidateOnFocus)
    }
  }, [gateway, handleSignedOut, refresh, routerCoordinator])

  const value = useMemo<AuthContextValue>(
    () => ({
      state,
      async signIn(email, password) {
        replaceState({ status: 'booting' })
        try {
          await clearSessionCache(queryClient)
          await gateway.signIn(email, password)
          await refresh()
          routerCoordinator.revalidate()
        } catch (error) {
          replaceState({ status: 'unauthenticated' })
          throw error
        }
      },
      async signOut() {
        try {
          ++requestGenerationRef.current
          replaceState({ status: 'booting' })
          authorizationSignals?.publish('signed-out')
          await clearSessionCache(queryClient)
          await gateway.signOut()
          replaceState({ status: 'unauthenticated' })
          await routerCoordinator.navigateToLogin()
        } catch {
          replaceState({ status: 'error' })
        }
      },
      async acceptInvitation(token, correlationId) {
        await gateway.acceptInvitation(token, correlationId)
        await refresh()
        routerCoordinator.revalidate()
      },
      resolveTenantRef: refresh,
      refreshSession: refresh,
    }),
    [authorizationSignals, gateway, queryClient, refresh, replaceState, routerCoordinator, state],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
