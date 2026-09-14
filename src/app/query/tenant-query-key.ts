import type { AuthorizationProjection } from '@/shared/authorization/authorization-projection'

type QueryKeyPart = Readonly<Record<string, unknown>> | string | number | boolean

export function tenantQueryKey(
  projection: AuthorizationProjection,
  authorizationGeneration: number,
  resource: string,
  ...parts: QueryKeyPart[]
) {
  return [
    'principal',
    projection.principalId,
    'tenant',
    projection.tenantId,
    'membership',
    projection.membershipId,
    projection.revision.membershipVersion,
    'profile',
    projection.profileId,
    projection.revision.profileVersion,
    'catalog',
    projection.revision.catalogRevision,
    'authorization',
    projection.authorizationRevision,
    'generation',
    authorizationGeneration,
    resource,
    ...parts,
  ] as const
}
