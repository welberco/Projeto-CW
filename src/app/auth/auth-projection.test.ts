import { describe, expect, it } from 'vitest'
import { normalizeInvitationEmail } from '@/shared/auth/auth-projection'

describe('auth input normalization', () => {

  it('normalizes invitation email with trim and lowercase only', () => {
    expect(normalizeInvitationEmail('  Person.Name@Example.COM  ')).toBe(
      'person.name@example.com',
    )
  })
})
