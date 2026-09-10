export function parseInvitationToken(hash: string): string | null {
  if (!hash.startsWith('#')) return null
  const token = new URLSearchParams(hash.slice(1)).get('token')
  return token !== null && /^[0-9a-f]{64}$/u.test(token) ? token : null
}
