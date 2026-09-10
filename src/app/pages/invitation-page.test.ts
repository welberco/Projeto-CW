import { describe, expect, it } from 'vitest'
import { parseInvitationToken } from '@/shared/auth/invitation-token'

describe('invitation token handling', () => {
  it('reads a valid token from the URL fragment only', () => {
    const token = 'a'.repeat(64)
    expect(parseInvitationToken(`#token=${token}`)).toBe(token)
  })

  it.each(['', '#token=short', `?token=${'a'.repeat(64)}`, `#token=${'A'.repeat(64)}`])(
    'rejects unsafe token input %s',
    (value) => expect(parseInvitationToken(value)).toBeNull(),
  )
})
