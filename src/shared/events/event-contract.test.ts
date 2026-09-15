import { describe, expect, it, vi } from 'vitest'
import { z } from 'zod'
import {
  canonicalizeSemanticInput,
  computeRetryDelaySeconds,
  createHandlerRegistry,
  sanitizeDeliveryError,
  semanticFingerprintSha256,
  type EventHandler,
  type OutboxEnvelope,
  type TechnicalExecutionContext,
} from '@/shared/events/event-contract'

const profileCreatedSchema = z
  .object({ profile_version: z.number().int().positive() })
  .strict()

function createEnvelope(
  overrides: Partial<OutboxEnvelope['event']> = {},
): OutboxEnvelope {
  return {
    event: {
      eventId: 'event-1',
      eventType: 'authorization.profile.created',
      eventVersion: 1,
      occurredAt: '2026-09-15T12:00:00.000Z',
      scope: { kind: 'tenant', tenantId: 'tenant-a' },
      commandId: 'command-1',
      correlationId: 'correlation-1',
      payload: { profile_version: 1 },
      metadata: {},
      ...overrides,
    },
    delivery: {
      status: 'pending',
      attemptCount: 0,
      nextAttemptAt: '2026-09-15T12:00:00.000Z',
    },
  }
}

const context: TechnicalExecutionContext = {
  consumerName: 'w3c.contract_probe',
  technicalActorRef: 'worker:w3c-contract-probe',
  tenantId: 'tenant-a',
  correlationId: 'correlation-1',
}

describe('W3C semantic fingerprint', () => {
  it('canonicalizes object keys recursively without changing array semantics', () => {
    expect(
      canonicalizeSemanticInput({
        profile: { status: 'active', name: 'Gestor' },
        permissions: ['read', 'write'],
      }),
    ).toBe(
      canonicalizeSemanticInput({
        permissions: ['read', 'write'],
        profile: { name: 'Gestor', status: 'active' },
      }),
    )

    expect(
      canonicalizeSemanticInput({ permissions: ['write', 'read'] }),
    ).not.toBe(canonicalizeSemanticInput({ permissions: ['read', 'write'] }))
  })

  it('creates a stable lowercase SHA-256 and changes with semantic intent', async () => {
    const first = await semanticFingerprintSha256({
      command_name: 'authorization.create_tenant_profile',
      profile_name: 'Gestor',
      command_reason: 'configuração inicial',
    })
    const reordered = await semanticFingerprintSha256({
      command_reason: 'configuração inicial',
      profile_name: 'Gestor',
      command_name: 'authorization.create_tenant_profile',
    })
    const changed = await semanticFingerprintSha256({
      command_name: 'authorization.create_tenant_profile',
      profile_name: 'Supervisor',
      command_reason: 'configuração inicial',
    })

    expect(first).toMatch(/^[0-9a-f]{64}$/)
    expect(reordered).toBe(first)
    expect(changed).not.toBe(first)
  })
})

describe('W3C allowlisted handler contract', () => {
  it('validates exact type/version and supplies a fixed capability', async () => {
    const handle = vi.fn<EventHandler['handle']>().mockResolvedValue({
      status: 'processed',
      result: { observed: true },
    })
    const handler: EventHandler = {
      handlerName: 'w3c_profile_created_probe',
      handlerVersion: 1,
      capability: 'authorization.profile.observe',
      handle,
    }
    const registry = createHandlerRegistry([
      {
        eventType: 'authorization.profile.created',
        eventVersion: 1,
        payloadSchema: profileCreatedSchema,
        handler,
      },
    ])

    await expect(registry.dispatch(createEnvelope(), context)).resolves.toEqual({
      status: 'processed',
      result: { observed: true },
    })
    expect(handle).toHaveBeenCalledWith(
      expect.objectContaining({ payload: { profile_version: 1 } }),
      expect.objectContaining({
        tenantId: 'tenant-a',
        capability: 'authorization.profile.observe',
      }),
    )
  })

  it('fails closed for unknown version, invalid payload and tenant mismatch', async () => {
    const handler: EventHandler = {
      handlerName: 'w3c_profile_created_probe',
      handlerVersion: 1,
      capability: 'authorization.profile.observe',
      handle() {
        return Promise.resolve({ status: 'processed', result: {} })
      },
    }
    const registry = createHandlerRegistry([
      {
        eventType: 'authorization.profile.created',
        eventVersion: 1,
        payloadSchema: profileCreatedSchema,
        handler,
      },
    ])

    await expect(
      registry.dispatch(createEnvelope({ eventVersion: 2 }), context),
    ).resolves.toEqual({
      status: 'terminal_failure',
      code: 'EVENT_CONTRACT_UNSUPPORTED',
    })
    await expect(
      registry.dispatch(
        createEnvelope({
          payload: { profile_version: 1, handler_name: 'forged' },
        }),
        context,
      ),
    ).resolves.toEqual({
      status: 'terminal_failure',
      code: 'EVENT_PAYLOAD_INVALID',
    })
    await expect(
      registry.dispatch(createEnvelope(), { ...context, tenantId: 'tenant-b' }),
    ).resolves.toEqual({
      status: 'terminal_failure',
      code: 'EVENT_TENANT_MISMATCH',
    })
  })

  it('rejects duplicate registry keys instead of selecting a handler ambiguously', () => {
    const handler: EventHandler = {
      handlerName: 'w3c_profile_created_probe',
      handlerVersion: 1,
      capability: 'authorization.profile.observe',
      handle() {
        return Promise.resolve({ status: 'processed', result: {} })
      },
    }
    const contract = {
      eventType: 'authorization.profile.created',
      eventVersion: 1,
      payloadSchema: profileCreatedSchema,
      handler,
    }

    expect(() => createHandlerRegistry([contract, contract])).toThrow(
      'Duplicate event contract: authorization.profile.created@1',
    )
  })
})

describe('W3D retry and safe-error contract', () => {
  const policy = { baseSeconds: 2, maxSeconds: 10, jitterPercent: 20 }

  it('applies capped exponential backoff with deterministic jitter bounds', () => {
    expect(computeRetryDelaySeconds(1, 0, policy)).toBe(1.6)
    expect(computeRetryDelaySeconds(2, 0.5, policy)).toBe(4)
    expect(computeRetryDelaySeconds(4, 1, policy)).toBe(12)
  })

  it('rejects invalid policy inputs instead of creating an unbounded retry', () => {
    expect(() => computeRetryDelaySeconds(0, 0.5, policy)).toThrow()
    expect(() => computeRetryDelaySeconds(1, 1.1, policy)).toThrow()
    expect(() =>
      computeRetryDelaySeconds(1, 0.5, { ...policy, jitterPercent: 101 }),
    ).toThrow()
  })

  it('normalizes operational errors and enforces the 500 character boundary', () => {
    expect(sanitizeDeliveryError(' temporary\nprovider failure ')).toBe(
      'temporary provider failure',
    )
    expect(() => sanitizeDeliveryError(`x${'y'.repeat(500)}`)).toThrow(
      'Unsafe delivery error.',
    )
  })

  it.each([
    'Authorization: Bearer synthetic-token-value',
    'eyJhbGciOiJub25lIn0.eyJzdWIiOiJzeW50aGV0aWMifQ.synthetic-signature',
    'https://storage.example.invalid/object?X-Amz-Signature=synthetic-signature',
    'https://api.example.invalid/callback?access_token=synthetic-access',
    'refresh_token=synthetic-refresh',
    'id_token: synthetic-id',
    'api_key=synthetic-api-key',
    'apikey: synthetic-apikey',
    'authorization=synthetic-authorization',
    'token=synthetic-token',
    'signature=synthetic-signature',
    'sig=synthetic-sig',
    'secret=synthetic-secret',
    'password=synthetic-password',
    'passwd: synthetic-passwd',
  ])('redacts credential-shaped error material: %s', (message) => {
    expect(sanitizeDeliveryError(message)).toBe(
      'Sensitive worker error details were redacted.',
    )
  })

  it('preserves similar operational wording without copying arbitrary credentials', () => {
    expect(
      sanitizeDeliveryError(
        'Token bucket exhausted; signature validation failed during secret rotation.',
      ),
    ).toBe(
      'Token bucket exhausted; signature validation failed during secret rotation.',
    )
  })
})
