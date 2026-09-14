import type { AppSupabaseClient } from '@/infrastructure/supabase/client'
import { AppError } from '@/shared/errors/app-error'
import {
  projectAuthorizationRow,
  type AuthorizationProjectionResolution,
} from '@/shared/authorization/authorization-projection'

export interface AuthorizationGateway {
  resolveProjection: () => Promise<AuthorizationProjectionResolution>
}

export function createAuthorizationGateway(
  client: AppSupabaseClient,
): AuthorizationGateway {
  return {
    async resolveProjection() {
      const { data, error } = await client.rpc('resolve_my_authorization')

      if (error !== null || data?.[0] === undefined) {
        throw new AppError({
          code: 'AUTHORIZATION_PROJECTION_UNAVAILABLE',
          category: 'unavailable',
          userMessage: 'Não foi possível verificar as permissões com segurança.',
        })
      }

      try {
        return projectAuthorizationRow(data[0])
      } catch {
        throw new AppError({
          code: 'AUTHORIZATION_PROJECTION_INVALID',
          category: 'unavailable',
          userMessage: 'Não foi possível verificar as permissões com segurança.',
        })
      }
    },
  }
}
