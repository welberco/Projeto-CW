import { Navigate } from 'react-router-dom'
import { useAuth } from '@/app/auth/use-auth'
import { SessionStatePage } from '@/app/pages/session-state-page'
import { canonicalTenantPath } from '@/app/router/tenant-route'

export function HomeRoutePage() {
  const { state, signOut } = useAuth()

  if (state.status === 'ready') {
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
