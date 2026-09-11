import { describe, expect, it } from 'vitest'
import { tenantQueryKey } from '@/app/query/tenant-query-key'

describe('tenant query keys', () => {
  it('partitions every key by principal, context generation, tenant and membership', () => {
    const key = tenantQueryKey(
      {
        principalId: 'principal-a',
        tenantId: 'tenant-a',
        membershipId: 'membership-a',
        membershipVersion: 3,
        contextGeneration: 7,
      },
      'work-orders',
      'list',
      { status: 'open' },
    )

    expect(key).toEqual([
      'principal',
      'principal-a',
      'context',
      7,
      'tenant',
      'tenant-a',
      'membership',
      'membership-a',
      3,
      'work-orders',
      'list',
      { status: 'open' },
    ])
  })
})
