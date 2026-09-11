import type { AppSupabaseClient } from '@/infrastructure/supabase/client'
import type { AuthChangeEvent } from '@supabase/supabase-js'
import { AppError } from '@/shared/errors/app-error'
import {
  parseTenantRef,
  projectTenantContextRow,
  type TenantContextResolution,
  type TenantContextRow,
} from '@/shared/session/tenant-context'

interface TenantContextRpcClient {
  rpc: (
    name: 'resolve_my_tenant_context',
    args: { target_tenant_ref?: string },
  ) => Promise<{ data: TenantContextRow[] | null; error: unknown }>
}

export interface AuthGateway {
  resolveSession: (targetTenantRef?: string | null) => Promise<TenantContextResolution>
  signIn: (email: string, password: string) => Promise<void>
  signOut: () => Promise<void>
  acceptInvitation: (token: string, correlationId: string) => Promise<void>
  onAuthChange: (listener: (event: AuthChangeEvent) => void) => () => void
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

async function resolveSession(
  client: AppSupabaseClient,
  targetTenantRef?: string | null,
): Promise<TenantContextResolution> {
  const { data: sessionData, error: sessionError } = await client.auth.getSession()

  if (sessionError !== null) {
    throw safeAuthError('AUTH_SESSION_UNAVAILABLE', 'unavailable')
  }

  const principalId = sessionData.session?.user.id
  if (principalId === undefined) return { status: 'unauthenticated' }

  let normalizedTenantRef: string | null = null
  if (targetTenantRef !== undefined && targetTenantRef !== null) {
    normalizedTenantRef = parseTenantRef(targetTenantRef)
    if (normalizedTenantRef === null) {
      return { status: 'tenant_context_unavailable', principalId }
    }
  }

  const resolverArguments =
    normalizedTenantRef === null
      ? {}
      : { target_tenant_ref: normalizedTenantRef }
  const contextClient = client as unknown as TenantContextRpcClient
  const { data, error } = await contextClient.rpc(
    'resolve_my_tenant_context',
    resolverArguments,
  )

  if (error !== null || data?.[0] === undefined) {
    throw safeAuthError('TENANT_CONTEXT_UNAVAILABLE', 'unavailable')
  }

  return projectTenantContextRow(data[0])
}

export function createAuthGateway(client: AppSupabaseClient): AuthGateway {
  return {
    resolveSession: (targetTenantRef) =>
      resolveSession(client, targetTenantRef),
    async signIn(email, password) {
      const { error } = await client.auth.signInWithPassword({ email, password })
      if (error !== null) {
        throw safeAuthError('AUTH_SIGN_IN_FAILED', 'unauthenticated')
      }
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
      const { data } = client.auth.onAuthStateChange((event) => {
        queueMicrotask(() => listener(event))
      })
      return () => data.subscription.unsubscribe()
    },
  }
}
