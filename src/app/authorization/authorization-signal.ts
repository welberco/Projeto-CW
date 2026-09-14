export type AuthorizationSignalType = 'authz-invalidated' | 'signed-out'

export interface AuthorizationSignalBus {
  publish: (type: AuthorizationSignalType) => void
  subscribe: (listener: (type: AuthorizationSignalType) => void) => () => void
  close: () => void
}

interface AuthorizationSignalMessage {
  protocol: 'cw-authz-v1'
  type: AuthorizationSignalType
  nonce: string
}

interface BroadcastChannelLike {
  postMessage: (message: AuthorizationSignalMessage) => void
  close: () => void
  addEventListener: (
    type: 'message',
    listener: (event: MessageEvent<unknown>) => void,
  ) => void
  removeEventListener: (
    type: 'message',
    listener: (event: MessageEvent<unknown>) => void,
  ) => void
}

type ChannelFactory = (name: string) => BroadcastChannelLike

let fallbackNonce = 0

function isAuthorizationSignalMessage(
  value: unknown,
): value is AuthorizationSignalMessage {
  if (typeof value !== 'object' || value === null) return false
  const candidate = value as Partial<AuthorizationSignalMessage>
  const keys = Object.keys(candidate)
  return (
    keys.length === 3 &&
    keys.every((key) => ['protocol', 'type', 'nonce'].includes(key)) &&
    candidate.protocol === 'cw-authz-v1' &&
    (candidate.type === 'authz-invalidated' ||
      candidate.type === 'signed-out') &&
    typeof candidate.nonce === 'string' &&
    candidate.nonce.length > 0 &&
    candidate.nonce.length <= 100
  )
}

function createNonce(): string {
  fallbackNonce += 1
  return globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${fallbackNonce}`
}

export function createAuthorizationSignalBus(
  channelFactory?: ChannelFactory,
): AuthorizationSignalBus {
  const factory =
    channelFactory ??
    (typeof globalThis.BroadcastChannel === 'function'
      ? (name: string) => new globalThis.BroadcastChannel(name)
      : undefined)
  const channel = factory?.('cw-authorization')
  const listeners = new Set<(type: AuthorizationSignalType) => void>()
  const seenRemoteNonces = new Set<string>()

  const handleMessage = (event: MessageEvent<unknown>) => {
    if (!isAuthorizationSignalMessage(event.data)) return
    if (seenRemoteNonces.has(event.data.nonce)) return
    seenRemoteNonces.add(event.data.nonce)
    if (seenRemoteNonces.size > 100) {
      const oldestNonce = seenRemoteNonces.values().next().value
      if (oldestNonce !== undefined) seenRemoteNonces.delete(oldestNonce)
    }
    for (const listener of listeners) listener(event.data.type)
  }

  channel?.addEventListener('message', handleMessage)

  return {
    publish(type) {
      channel?.postMessage({
        protocol: 'cw-authz-v1',
        type,
        nonce: createNonce(),
      })
    },
    subscribe(listener) {
      listeners.add(listener)
      return () => listeners.delete(listener)
    },
    close() {
      channel?.removeEventListener('message', handleMessage)
      channel?.close()
      listeners.clear()
      seenRemoteNonces.clear()
    },
  }
}
