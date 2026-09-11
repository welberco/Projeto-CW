import type { AppSupabaseClient } from '@/infrastructure/supabase/client'
import {
  projectAuthAccess,
  type AuthAccessState,
} from '@/shared/auth/auth-projection'
import { AppError } from '@/shared/errors/app-error'

export interface AuthGateway {
  getAccessState: () => Promise<AuthAccessState>
  signIn: (email: string, password: string) => Promise<AuthAccessState>
  signOut: () => Promise<void>
  acceptInvitation: (token: string, correlationId: string) => Promise<void>
  onAuthChange: (listener: () => void) => () => void
}

function safeAuthError(code: string, category: 'unauthenticated' | 'unavailable') {
  return new AppError({
    code,
    category,
    userMessage:
      category === 'unauthenticated'
        ? 'Não foi possível entrar com as credenciais informadas.'
        : 'Não foi possível verificar o acesso com segurança.',
  })
}

async function loadAccessState(
  client: AppSupabaseClient,
): Promise<AuthAccessState> {
  const { data: sessionData, error: sessionError } = await client.auth.getSession()

  if (sessionError !== null) {
    throw safeAuthError('AUTH_SESSION_UNAVAILABLE', 'unavailable')
  }

  const userId = sessionData.session?.user.id
  if (userId === undefined) {
    return { status: 'anonymous' }
  }

  const { data: appUser, error: appUserError } = await client
    .from('app_users')
    .select('status')
    .eq('id', userId)
    .maybeSingle()

  if (appUserError !== null) {
    throw safeAuthError('AUTH_PROJECTION_UNAVAILABLE', 'unavailable')
  }

  if (appUser === null) {
    return projectAuthAccess({
      userId,
      appUserStatus: null,
      membershipStatus: null,
      tenantAvailable: false,
      maintenanceEnabled: false,
    })
  }

  const { data: memberships, error: membershipError } = await client
    .from('tenant_memberships')
    .select('tenant_id,status')
    .eq('user_id', userId)
    .in('status', ['active', 'blocked'])
    .limit(1)

  if (membershipError !== null) {
    throw safeAuthError('AUTH_PROJECTION_UNAVAILABLE', 'unavailable')
  }

  const membership = memberships[0]
  if (membership === undefined || membership.status !== 'active') {
    return projectAuthAccess({
      userId,
      appUserStatus: appUser.status,
      membershipStatus: membership?.status ?? null,
      tenantAvailable: false,
      maintenanceEnabled: false,
    })
  }

  const [{ data: tenant, error: tenantError }, { data: entitlement, error: entitlementError }] =
    await Promise.all([
      client
        .from('tenants')
        .select('id')
        .eq('id', membership.tenant_id)
        .maybeSingle(),
      client
        .from('tenant_entitlements')
        .select('enabled')
        .eq('tenant_id', membership.tenant_id)
        .eq('module_key', 'maintenance')
        .maybeSingle(),
    ])

  if (tenantError !== null || entitlementError !== null) {
    throw safeAuthError('AUTH_PROJECTION_UNAVAILABLE', 'unavailable')
  }

  return projectAuthAccess({
    userId,
    appUserStatus: appUser.status,
    membershipStatus: membership.status,
    tenantAvailable: tenant !== null,
    maintenanceEnabled: entitlement?.enabled === true,
  })
}

export function createAuthGateway(client: AppSupabaseClient): AuthGateway {
  return {
    getAccessState: () => loadAccessState(client),
    async signIn(email, password) {
      const { error } = await client.auth.signInWithPassword({ email, password })
      if (error !== null) {
        throw safeAuthError('AUTH_SIGN_IN_FAILED', 'unauthenticated')
      }
      return loadAccessState(client)
    },
    async signOut() {
      const { error } = await client.auth.signOut()
      if (error !== null) {
        throw safeAuthError('AUTH_SIGN_OUT_FAILED', 'unavailable')
      }
    },
    async acceptInvitation(token, correlationId) {
      const { error } = await client.rpc('accept_tenant_invitation', {
        invitation_token: token,
        correlation_id: correlationId,
      })
      if (error !== null) {
        throw new AppError({
          code: 'INVITATION_UNAVAILABLE',
          category: 'invalid_state',
          userMessage: 'Este convite não está disponível para esta conta.',
        })
      }
    },
    onAuthChange(listener) {
      const { data } = client.auth.onAuthStateChange(() => {
        queueMicrotask(listener)
      })
      return () => data.subscription.unsubscribe()
    },
  }
}
