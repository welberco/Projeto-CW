import { Navigate } from 'react-router-dom'
import { useAuth } from '@/app/auth/use-auth'
import { canonicalTenantPath } from '@/app/router/tenant-route'

export function TenantIndexPage() {
  const { state } = useAuth()

  if (state.status !== 'ready') return null

  return (
    <Navigate
      replace
      to={canonicalTenantPath(state.context.tenantRef, 'dashboard')}
    />
  )
}
