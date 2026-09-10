import { describe, expect, it } from 'vitest'
import {
  normalizeInvitationEmail,
  projectAuthAccess,
} from '@/shared/auth/auth-projection'

const userId = 'user-1'

describe('auth projection', () => {
  it.each([
    [null, 'profile_missing'],
    ['blocked', 'blocked'],
    ['inactive', 'inactive'],
  ] as const)('maps application lifecycle %s safely', (status, expected) => {
    expect(
      projectAuthAccess({
        userId,
        appUserStatus: status,
        membershipStatus: 'active',
        tenantAvailable: true,
        maintenanceEnabled: true,
      }).status,
    ).toBe(expected)
  })

  it.each([
    ['blocked', true, true],
    ['revoked', true, true],
    [null, true, true],
    ['active', false, true],
    ['active', true, false],
  ] as const)(
    'fails closed for membership=%s tenant=%s entitlement=%s',
    (membershipStatus, tenantAvailable, maintenanceEnabled) => {
      expect(
        projectAuthAccess({
          userId,
          appUserStatus: 'active',
          membershipStatus,
          tenantAvailable,
          maintenanceEnabled,
        }).status,
      ).toBe('no_access')
    },
  )

  it('recognizes only a fully operational projection', () => {
    expect(
      projectAuthAccess({
        userId,
        appUserStatus: 'active',
        membershipStatus: 'active',
        tenantAvailable: true,
        maintenanceEnabled: true,
      }),
    ).toEqual({ status: 'authenticated', userId })
  })

  it('normalizes invitation email with trim and lowercase only', () => {
    expect(normalizeInvitationEmail('  Person.Name@Example.COM  ')).toBe(
      'person.name@example.com',
    )
  })
})
