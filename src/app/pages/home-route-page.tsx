import { Navigate } from 'react-router-dom'
import { useAuth } from '@/app/auth/use-auth'
import { useAuthorization } from '@/app/authorization/use-authorization'
import { AuthorizationStatePage } from '@/app/pages/authorization-state-page'
import { SessionStatePage } from '@/app/pages/session-state-page'
import { canonicalTenantPath } from '@/app/router/tenant-route'

export function HomeRoutePage() {
  const { state, signOut } = useAuth()
  const { state: authorizationState } = useAuthorization()

  if (state.status === 'ready') {
    if (authorizationState.status !== 'ready') {
      return (
        <div className="px-4 py-10 sm:px-6">
          <AuthorizationStatePage
            state={authorizationState}
            onSignOut={signOut}
          />
        </div>
      )
    }
    return (
      <Navigate replace to={canonicalTenantPath(state.context.tenantRef)} />
    )
  }

  if (state.status === 'unauthenticated') {
    return <Navigate replace to="/login" />
  }

  return (
    <div className="px-4 py-10 sm:px-6">
      <SessionStatePage state={state} onSignOut={signOut} />
    </div>
  )
}
