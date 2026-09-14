import { describe, expect, it } from 'vitest'
import { tenantQueryKey } from '@/app/query/tenant-query-key'

describe('tenant query keys', () => {
  const projection = {
    principalId: 'principal-a',
    tenantId: 'tenant-a',
    tenantRef: '34000000-0000-4000-8000-000000000001',
    membershipId: 'membership-a',
    profileId: 'profile-a',
    profileName: 'Profile A',
    revision: {
      membershipVersion: 3,
      profileVersion: 5,
      catalogRevision: 11,
    },
    authorizationRevision: 'm3:p5:c11',
    permissionCodes: [],
    enabledEntitlements: [],
  }

  it('partitions every key by the complete authorization identity and revision', () => {
    const key = tenantQueryKey(
      projection,
      7,
      'work-orders',
      'list',
      { status: 'open' },
    )

    expect(key).toEqual([
      'principal',
      'principal-a',
      'tenant',
      'tenant-a',
      'membership',
      'membership-a',
      3,
      'profile',
      'profile-a',
      5,
      'catalog',
      11,
      'authorization',
      'm3:p5:c11',
      'generation',
      7,
      'work-orders',
      'list',
      { status: 'open' },
    ])
  })

  it('is deterministic for an unchanged projection and filters', () => {
    expect(tenantQueryKey(projection, 7, 'users', { active: true })).toEqual(
      tenantQueryKey(projection, 7, 'users', { active: true }),
    )
  })

  it.each([
    ['principal', { principalId: 'principal-b' }, 7],
    ['tenant', { tenantId: 'tenant-b' }, 7],
    ['membership version', { revision: { ...projection.revision, membershipVersion: 4 } }, 7],
    ['profile version', { revision: { ...projection.revision, profileVersion: 6 } }, 7],
    ['catalog revision', { revision: { ...projection.revision, catalogRevision: 12 } }, 7],
    ['authorization revision', { authorizationRevision: 'm4:p5:c11' }, 7],
    ['local generation', {}, 8],
  ])('separates a changed %s', (_label, patch, generation) => {
    expect(tenantQueryKey({ ...projection, ...patch }, generation, 'users')).not.toEqual(
      tenantQueryKey(projection, 7, 'users'),
    )
  })
})
