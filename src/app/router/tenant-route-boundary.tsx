import { useEffect, useRef, useState } from 'react'
import { Outlet, useParams } from 'react-router-dom'
import { useAuth } from '@/app/auth/use-auth'
import { TenantAppShell } from '@/app/layout/tenant-app-shell'
import { SessionStatePage } from '@/app/pages/session-state-page'
import { tenantRouteMatches } from '@/app/router/tenant-route'

export function TenantRouteBoundary() {
  const { tenantRef } = useParams<{ tenantRef: string }>()
  const { state, resolveTenantRef, signOut } = useAuth()
  const validationInFlightRef = useRef<string | null>(null)
  const [validatedContextKey, setValidatedContextKey] = useState<string | null>(
    null,
  )

  useEffect(() => {
    if (tenantRef === undefined || state.status !== 'ready') return

    const contextKey = `${state.context.contextGeneration}:${tenantRef}`
    if (
      validatedContextKey === contextKey ||
      validationInFlightRef.current === contextKey
    ) {
      return
    }

    validationInFlightRef.current = contextKey
    void resolveTenantRef(tenantRef).finally(() => {
      if (validationInFlightRef.current !== contextKey) return
      validationInFlightRef.current = null
      setValidatedContextKey(contextKey)
    })
  }, [resolveTenantRef, state, tenantRef, validatedContextKey])

  const currentContextKey =
    state.status === 'ready' && tenantRef !== undefined
      ? `${state.context.contextGeneration}:${tenantRef}`
      : null

  if (state.status === 'ready' && validatedContextKey !== currentContextKey) {
    return (
      <div className="px-4 py-10 sm:px-6">
        <SessionStatePage state={{ status: 'booting' }} onSignOut={signOut} />
      </div>
    )
  }

  if (state.status !== 'ready') {
    return (
      <div className="px-4 py-10 sm:px-6">
        <SessionStatePage state={state} onSignOut={signOut} />
      </div>
    )
  }

  if (!tenantRouteMatches(tenantRef, state.context.tenantRef)) {
    return (
      <div className="px-4 py-10 sm:px-6">
        <SessionStatePage
          state={{
            status: 'tenant_context_unavailable',
            principalId: state.context.principalId,
          }}
          onSignOut={signOut}
        />
      </div>
    )
  }

  return (
    <TenantAppShell context={state.context} onSignOut={signOut}>
      <Outlet />
    </TenantAppShell>
  )
}
