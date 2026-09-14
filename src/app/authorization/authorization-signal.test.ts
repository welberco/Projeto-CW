import { afterEach, describe, expect, it, vi } from 'vitest'
import { createAuthorizationSignalBus } from '@/app/authorization/authorization-signal'

function setup() {
  let messageListener: ((event: MessageEvent<unknown>) => void) | undefined
  let publishedMessage: unknown
  const postMessage = vi.fn((message: unknown) => {
    publishedMessage = message
  })
  const close = vi.fn()
  const removeEventListener = vi.fn()
  const bus = createAuthorizationSignalBus(() => ({
    postMessage,
    close,
    addEventListener(_type, listener) {
      messageListener = listener
    },
    removeEventListener,
  }))

  return {
    bus,
    close,
    getListener: () => messageListener,
    getPublishedMessage: () => publishedMessage,
    postMessage,
    removeEventListener,
  }
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('authorization cross-tab signal bus', () => {
  it('publishes only a minimal invalidation signal without capability payloads', () => {
    const test = setup()
    test.bus.publish('authz-invalidated')

    expect(test.postMessage).toHaveBeenCalledOnce()
    const published = test.getPublishedMessage()
    expect(published).toEqual({
      protocol: 'cw-authz-v1',
      type: 'authz-invalidated',
      nonce:
        typeof published === 'object' && published !== null && 'nonce' in published
          ? published.nonce
          : undefined,
    })
    if (typeof published !== 'object' || published === null) {
      throw new Error('Expected a structured signal message.')
    }
    expect(Object.keys(published)).toEqual([
      'protocol',
      'type',
      'nonce',
    ])
    expect('nonce' in published && typeof published.nonce).toBe('string')
  })

  it('reconsults subscribers only for an exact valid remote protocol message', () => {
    const test = setup()
    const subscriber = vi.fn()
    test.bus.subscribe(subscriber)

    test.getListener()?.(
      new MessageEvent('message', {
        data: { protocol: 'cw-authz-v1', type: 'signed-out', nonce: 'remote-1' },
      }),
    )
    test.getListener()?.(
      new MessageEvent('message', {
        data: {
          protocol: 'cw-authz-v1',
          type: 'authz-invalidated',
          nonce: 'forged',
          permissionCodes: ['core.users.read.all_tenant'],
        },
      }),
    )
    test.getListener()?.(
      new MessageEvent('message', {
        data: { protocol: 'wrong', type: 'authz-invalidated', nonce: 'remote-2' },
      }),
    )

    expect(subscriber).toHaveBeenCalledOnce()
    expect(subscriber).toHaveBeenCalledWith('signed-out')
  })

  it('rejects manipulated payloads and ignores a replayed nonce', () => {
    const test = setup()
    const subscriber = vi.fn()
    test.bus.subscribe(subscriber)
    const listener = test.getListener()

    for (const data of [
      null,
      'signed-out',
      { protocol: 'cw-authz-v1', type: 'unknown', nonce: 'n-1' },
      { protocol: 'cw-authz-v1', type: 'authz-invalidated', nonce: '' },
      { protocol: 'cw-authz-v1', type: 'authz-invalidated', nonce: 'n-2', admin: true },
      { protocol: 'cw-authz-v1', type: 'authz-invalidated', nonce: 'n-3', tenant_id: 'tenant-b' },
      { protocol: 'cw-authz-v1', type: 'authz-invalidated', nonce: 'n-4', actor: 'principal-b' },
      { protocol: 'cw-authz-v1', type: 'authz-invalidated', nonce: 'n-5', permissions: ['*'] },
    ]) {
      listener?.(new MessageEvent('message', { data }))
    }

    const valid = {
      protocol: 'cw-authz-v1',
      type: 'authz-invalidated',
      nonce: 'remote-once',
    }
    listener?.(new MessageEvent('message', { data: valid }))
    listener?.(new MessageEvent('message', { data: valid }))

    expect(subscriber).toHaveBeenCalledOnce()
    expect(subscriber).toHaveBeenCalledWith('authz-invalidated')
  })

  it('does not echo a local publication and cleans up listeners', () => {
    const test = setup()
    const subscriber = vi.fn()
    const unsubscribe = test.bus.subscribe(subscriber)

    test.bus.publish('signed-out')
    expect(subscriber).not.toHaveBeenCalled()

    unsubscribe()
    test.bus.close()
    expect(test.removeEventListener).toHaveBeenCalledOnce()
    expect(test.close).toHaveBeenCalledOnce()
  })

  it('degrades safely when BroadcastChannel is unavailable', () => {
    vi.stubGlobal('BroadcastChannel', undefined)
    const bus = createAuthorizationSignalBus()
    const subscriber = vi.fn()

    expect(() => bus.publish('authz-invalidated')).not.toThrow()
    expect(() => bus.subscribe(subscriber)()).not.toThrow()
    expect(() => bus.close()).not.toThrow()
    expect(subscriber).not.toHaveBeenCalled()
  })
})
