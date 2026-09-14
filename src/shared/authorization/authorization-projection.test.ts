import { describe, expect, it } from 'vitest'
import {
  authorizationProjectionSemanticKey,
  hasProjectedEntitlement,
  hasProjectedPermission,
  projectAuthorizationRow,
  serializeAuthorizationRevision,
  type AuthorizationProjection,
  type AuthorizationProjectionRow,
} from '@/shared/authorization/authorization-projection'

const readyRow: AuthorizationProjectionRow = {
  projection_status: 'ready',
  principal_id: 'principal-a',
  tenant_id: 'tenant-a',
  tenant_ref: '34000000-0000-4000-8000-000000000001',
  membership_id: 'membership-a',
  membership_version: 3,
  profile_id: 'profile-a',
  profile_version: 5,
  profile_name: 'Gestor',
  catalog_revision: 12,
  authorization_revision: 'm3:p5:c12',
  permission_codes: [
    'core.profiles.read.all_tenant',
    'core.users.read.all_tenant',
  ],
  enabled_entitlements: ['maintenance'],
}

function readyProjection(): AuthorizationProjection {
  const result = projectAuthorizationRow(readyRow)
  if (result.status !== 'ready') throw new Error('Expected ready projection.')
  return result.projection
}

describe('authoritative authorization projection', () => {
  it('maps a complete, canonical and sorted ready projection', () => {
    expect(projectAuthorizationRow(readyRow)).toEqual({
      status: 'ready',
      projection: {
        principalId: 'principal-a',
        tenantId: 'tenant-a',
        tenantRef: '34000000-0000-4000-8000-000000000001',
        membershipId: 'membership-a',
        profileId: 'profile-a',
        profileName: 'Gestor',
        revision: {
          membershipVersion: 3,
          profileVersion: 5,
          catalogRevision: 12,
        },
        authorizationRevision: 'm3:p5:c12',
        permissionCodes: readyRow.permission_codes,
        enabledEntitlements: ['maintenance'],
      },
    })
  })

  it('maps only explicit unauthenticated and unavailable states', () => {
    expect(
      projectAuthorizationRow({ ...readyRow, projection_status: 'unauthenticated' }),
    ).toEqual({ status: 'unauthenticated' })
    expect(
      projectAuthorizationRow({
        ...readyRow,
        projection_status: 'profile_unavailable',
      }),
    ).toEqual({ status: 'profile_unavailable', principalId: 'principal-a' })
  })

  it.each([
    ['partial row', { tenant_id: null }],
    ['noncanonical revision', { authorization_revision: 'm3-p5-c12' }],
    ['zero version', { profile_version: 0, authorization_revision: 'm3:p0:c12' }],
    [
      'unsorted permissions',
      {
        permission_codes: [
          'core.users.read.all_tenant',
          'core.profiles.read.all_tenant',
        ],
      },
    ],
    ['duplicate entitlements', { enabled_entitlements: ['maintenance', 'maintenance'] }],
    ['wildcard permission', { permission_codes: ['core.users.*.all_tenant'] }],
  ])('rejects an invalid %s', (_label, patch) => {
    expect(() => projectAuthorizationRow({ ...readyRow, ...patch })).toThrow(
      'Invalid authoritative authorization projection.',
    )
  })

  it('serializes and keys every mutable authorization dimension', () => {
    const projection = readyProjection()
    expect(serializeAuthorizationRevision(projection.revision)).toBe('m3:p5:c12')

    const original = authorizationProjectionSemanticKey(projection)
    for (const changed of [
      { ...projection, principalId: 'principal-b' },
      { ...projection, tenantId: 'tenant-b' },
      { ...projection, membershipId: 'membership-b' },
      { ...projection, profileId: 'profile-b' },
      { ...projection, authorizationRevision: 'm4:p5:c12' },
      { ...projection, permissionCodes: [] },
      { ...projection, enabledEntitlements: [] },
    ]) {
      expect(authorizationProjectionSemanticKey(changed)).not.toBe(original)
    }
  })

  it('checks exact permission codes and separate entitlements without hierarchy', () => {
    const projection = readyProjection()
    expect(hasProjectedPermission(projection, 'core.users.read.all_tenant')).toBe(true)
    expect(hasProjectedPermission(projection, 'core.users.read.own')).toBe(false)
    expect(hasProjectedPermission(projection, 'core.users.*.all_tenant')).toBe(false)
    expect(hasProjectedEntitlement(projection, 'maintenance')).toBe(true)
    expect(hasProjectedEntitlement(projection, 'maintenance.admin')).toBe(false)
  })
})
