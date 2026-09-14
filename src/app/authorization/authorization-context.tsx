import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import type { QueryClient } from '@tanstack/react-query'
import {
  AuthorizationContext,
  type AuthorizationContextValue,
  type AuthorizationState,
} from '@/app/authorization/use-authorization'
import type { AuthorizationSignalBus } from '@/app/authorization/authorization-signal'
import { useAuth } from '@/app/auth/use-auth'
import { clearSessionCache } from '@/app/query/session-cache-coordinator'
import type { AuthorizationGateway } from '@/infrastructure/supabase/authorization-gateway'
import {
  authorizationProjectionSemanticKey,
  hasProjectedEntitlement,
  hasProjectedPermission,
  type AuthorizationProjection,
} from '@/shared/authorization/authorization-projection'
import type { AuthorizedTenantContext, SessionState } from '@/shared/session/tenant-context'

const authorizationRevalidationIntervalMs = 30_000

function tenantContextKey(context: AuthorizedTenantContext): string {
  return [
    context.principalId,
    context.tenantId,
    context.membershipId,
    context.membershipVersion,
    context.contextGeneration,
  ].join('|')
}

function projectionMatchesTenantContext(
  projection: AuthorizationProjection,
  context: AuthorizedTenantContext,
): boolean {
  return (
    projection.principalId === context.principalId &&
    projection.tenantId === context.tenantId &&
    projection.tenantRef === context.tenantRef &&
    projection.membershipId === context.membershipId &&
    projection.revision.membershipVersion === context.membershipVersion
  )
}

export function AuthorizationProvider({
  children,
  gateway,
  queryClient,
  signalBus,
  revalidationIntervalMs = authorizationRevalidationIntervalMs,
}: {
  children: ReactNode
  gateway: AuthorizationGateway
  queryClient: QueryClient
  signalBus: AuthorizationSignalBus
  revalidationIntervalMs?: number
}) {
  const { state: sessionState } = useAuth()
  const [state, setState] = useState<AuthorizationState>({ status: 'idle' })
  const stateRef = useRef<AuthorizationState>({ status: 'idle' })
  const sessionStateRef = useRef<SessionState>(sessionState)
  const requestGenerationRef = useRef(0)
  const authorizationGenerationRef = useRef(0)
  const semanticKeyRef = useRef<string | null>(null)
  const lastReadySessionKeyRef = useRef<string | null>(null)
  const mountedRef = useRef(true)

  const markUnmounted = useCallback(() => {
    mountedRef.current = false
    ++requestGenerationRef.current
  }, [])

  useEffect(() => {
    mountedRef.current = true
    return markUnmounted
  }, [markUnmounted])

  useEffect(() => {
    sessionStateRef.current = sessionState
  }, [sessionState])

  const replaceState = useCallback((nextState: AuthorizationState) => {
    if (!mountedRef.current) return
    stateRef.current = nextState
    setState(nextState)
  }, [])

  const bumpGeneration = useCallback(() => {
    authorizationGenerationRef.current += 1
    return authorizationGenerationRef.current
  }, [])

  const clearSensitiveState = useCallback(async () => {
    await clearSessionCache(queryClient)
    semanticKeyRef.current = null
    bumpGeneration()
  }, [bumpGeneration, queryClient])

  const refreshAuthorization = useCallback(async () => {
    const currentSession = sessionStateRef.current
    if (currentSession.status !== 'ready') return

    const expectedContext = currentSession.context
    const expectedContextKey = tenantContextKey(expectedContext)
    const requestGeneration = ++requestGenerationRef.current
    replaceState(
      stateRef.current.status === 'ready'
        ? { status: 'refreshing' }
        : { status: 'loading' },
    )

    try {
      const resolution = await gateway.resolveProjection()
      if (
        requestGeneration !== requestGenerationRef.current ||
        sessionStateRef.current.status !== 'ready' ||
        tenantContextKey(sessionStateRef.current.context) !== expectedContextKey
      ) {
        return
      }

      if (
        resolution.status !== 'ready' ||
        !projectionMatchesTenantContext(resolution.projection, expectedContext)
      ) {
        await clearSensitiveState()
        if (requestGeneration !== requestGenerationRef.current) return
        if (resolution.status === 'unauthenticated') {
          replaceState({ status: 'unauthenticated' })
          return
        }
        replaceState({
          status: 'unavailable',
          reason:
            resolution.status === 'ready'
              ? 'context_mismatch'
              : resolution.status,
        })
        return
      }

      const nextSemanticKey = authorizationProjectionSemanticKey(
        resolution.projection,
      )
      if (
        semanticKeyRef.current !== null &&
        semanticKeyRef.current !== nextSemanticKey
      ) {
        await clearSessionCache(queryClient)
        if (requestGeneration !== requestGenerationRef.current) return
        bumpGeneration()
      }

      if (authorizationGenerationRef.current === 0) bumpGeneration()
      semanticKeyRef.current = nextSemanticKey
      replaceState({
        status: 'ready',
        projection: resolution.projection,
        authorizationGeneration: authorizationGenerationRef.current,
      })
    } catch {
      if (requestGeneration !== requestGenerationRef.current) return
      await clearSensitiveState()
      if (requestGeneration !== requestGenerationRef.current) return
      replaceState({ status: 'unavailable', reason: 'network' })
    }
  }, [bumpGeneration, clearSensitiveState, gateway, queryClient, replaceState])

  const invalidateAuthorization = useCallback(async () => {
    ++requestGenerationRef.current
    replaceState({ status: 'loading' })
    await clearSensitiveState()
    signalBus.publish('authz-invalidated')
    await refreshAuthorization()
  }, [clearSensitiveState, refreshAuthorization, replaceState, signalBus])

  const invalidateFromSignal = useCallback(async () => {
    ++requestGenerationRef.current
    replaceState({ status: 'loading' })
    await clearSensitiveState()
    await refreshAuthorization()
  }, [clearSensitiveState, refreshAuthorization, replaceState])

  useEffect(() => {
    const currentSession = sessionState

    if (currentSession.status === 'booting') {
      ++requestGenerationRef.current
      replaceState({ status: 'loading' })
      return
    }

    if (currentSession.status !== 'ready') {
      ++requestGenerationRef.current
      const hadReadyContext = lastReadySessionKeyRef.current !== null
      lastReadySessionKeyRef.current = null
      semanticKeyRef.current = null
      if (hadReadyContext) {
        void clearSensitiveState()
      }
      replaceState(
        currentSession.status === 'unauthenticated'
          ? { status: 'unauthenticated' }
          : currentSession.status === 'error'
            ? { status: 'unavailable', reason: 'network' }
            : { status: 'idle' },
      )
      return
    }

    const nextSessionKey = tenantContextKey(currentSession.context)
    const contextChanged =
      lastReadySessionKeyRef.current !== null &&
      lastReadySessionKeyRef.current !== nextSessionKey
    lastReadySessionKeyRef.current = nextSessionKey

    if (contextChanged) {
      ++requestGenerationRef.current
      replaceState({ status: 'loading' })
      void clearSensitiveState().then(refreshAuthorization)
      return
    }

    void refreshAuthorization()
  }, [clearSensitiveState, refreshAuthorization, replaceState, sessionState])

  useEffect(() => {
    return signalBus.subscribe((type) => {
      if (type === 'signed-out') {
        ++requestGenerationRef.current
        replaceState({ status: 'unauthenticated' })
        void clearSensitiveState()
        return
      }
      void invalidateFromSignal()
    })
  }, [clearSensitiveState, invalidateFromSignal, replaceState, signalBus])

  useEffect(() => {
    let intervalId: number | undefined

    const stopInterval = () => {
      if (intervalId === undefined) return
      window.clearInterval(intervalId)
      intervalId = undefined
    }

    const canRevalidate = () =>
      !document.hidden && navigator.onLine && sessionStateRef.current.status === 'ready'

    const startInterval = () => {
      stopInterval()
      if (!canRevalidate()) return
      intervalId = window.setInterval(() => {
        if (canRevalidate()) void refreshAuthorization()
      }, revalidationIntervalMs)
    }

    const handleFocus = () => {
      if (canRevalidate()) void refreshAuthorization()
    }
    const handleVisibility = () => {
      if (canRevalidate()) void refreshAuthorization()
      startInterval()
    }

    startInterval()
    window.addEventListener('focus', handleFocus)
    window.addEventListener('online', handleVisibility)
    window.addEventListener('offline', stopInterval)
    document.addEventListener('visibilitychange', handleVisibility)

    return () => {
      stopInterval()
      window.removeEventListener('focus', handleFocus)
      window.removeEventListener('online', handleVisibility)
      window.removeEventListener('offline', stopInterval)
      document.removeEventListener('visibilitychange', handleVisibility)
    }
  }, [refreshAuthorization, revalidationIntervalMs])

  const exposedState = useMemo<AuthorizationState>(() => {
    if (
      state.status === 'ready' &&
      sessionState.status === 'ready' &&
      projectionMatchesTenantContext(state.projection, sessionState.context)
    ) {
      return state
    }
    if (state.status === 'unauthenticated') return state
    if (sessionState.status === 'unauthenticated') return { status: 'unauthenticated' }
    if (state.status === 'unavailable') return state
    return state.status === 'refreshing' ? { status: 'refreshing' } : { status: 'loading' }
  }, [sessionState, state])

  const value = useMemo<AuthorizationContextValue>(
    () => ({
      state: exposedState,
      refreshAuthorization,
      invalidateAuthorization,
      hasPermission(permissionCode) {
        return exposedState.status === 'ready'
          ? hasProjectedPermission(exposedState.projection, permissionCode)
          : false
      },
      hasEntitlement(entitlementKey) {
        return exposedState.status === 'ready'
          ? hasProjectedEntitlement(exposedState.projection, entitlementKey)
          : false
      },
    }),
    [exposedState, invalidateAuthorization, refreshAuthorization],
  )

  return (
    <AuthorizationContext.Provider value={value}>
      {children}
    </AuthorizationContext.Provider>
  )
}
