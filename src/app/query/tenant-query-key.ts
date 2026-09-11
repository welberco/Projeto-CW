import type { ContextIdentity } from '@/shared/session/tenant-context'

type QueryKeyPart = Readonly<Record<string, unknown>> | string | number | boolean

export function tenantQueryKey(
  context: ContextIdentity,
  resource: string,
  ...parts: QueryKeyPart[]
) {
  return [
    'principal',
    context.principalId,
    'context',
    context.contextGeneration,
    'tenant',
    context.tenantId,
    'membership',
    context.membershipId,
    context.membershipVersion,
    resource,
    ...parts,
  ] as const
}
