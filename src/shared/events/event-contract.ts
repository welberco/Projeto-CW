import { z } from 'zod'

export type EventScope =
  | Readonly<{ kind: 'tenant'; tenantId: string }>
  | Readonly<{ kind: 'platform' }>

export interface DomainEvent<
  TType extends string = string,
  TVersion extends number = number,
  TPayload = unknown,
> {
  readonly eventId: string
  readonly eventType: TType
  readonly eventVersion: TVersion
  readonly occurredAt: string
  readonly scope: EventScope
  readonly commandId: string
  readonly correlationId: string
  readonly causationId?: string
  readonly aggregate?: Readonly<{
    type: string
    id: string
    version?: number
  }>
  readonly payload: TPayload
  readonly metadata: Readonly<Record<string, unknown>>
}

export interface OutboxEnvelope<TEvent extends DomainEvent = DomainEvent> {
  readonly event: TEvent
  readonly delivery: Readonly<{
    status: 'pending' | 'processing' | 'processed' | 'dead_letter'
    attemptCount: number
    nextAttemptAt: string
    claimedBy?: string
    leaseExpiresAt?: string
    leaseToken?: string
    fencingToken?: number
  }>
}

export type RetryClassification =
  | Readonly<{ kind: 'retryable'; code: string }>
  | Readonly<{ kind: 'terminal'; code: string }>

export type HandlerResult =
  | Readonly<{ status: 'processed'; result: Readonly<Record<string, unknown>> }>
  | Readonly<{ status: 'duplicate'; result: Readonly<Record<string, unknown>> }>
  | Readonly<{ status: 'retryable_failure'; code: string }>
  | Readonly<{ status: 'terminal_failure'; code: string }>

export interface TechnicalExecutionContext {
  readonly consumerName: string
  readonly technicalActorRef: string
  readonly tenantId: string
  readonly correlationId: string
}

export interface EventHandler<
  TEvent extends DomainEvent = DomainEvent,
  TCapability extends string = string,
> {
  readonly handlerName: string
  readonly handlerVersion: number
  readonly capability: TCapability
  handle(
    event: TEvent,
    context: TechnicalExecutionContext & Readonly<{ capability: TCapability }>,
  ): Promise<HandlerResult>
}

export type CommandIdempotencyResult<TResult> =
  | Readonly<{ kind: 'executed'; commandId: string; result: TResult }>
  | Readonly<{ kind: 'replayed'; commandId: string; result: TResult }>

export interface HistoryEntryProjection<TPayload> {
  readonly id: string
  readonly aggregateType: string
  readonly aggregateId: string
  readonly historyType: string
  readonly historyVersion: number
  readonly occurredAt: string
  readonly payload: TPayload
}

type SemanticPrimitive = null | boolean | number | string
export type SemanticValue =
  | SemanticPrimitive
  | readonly SemanticValue[]
  | Readonly<{ [key: string]: SemanticValue }>

function isSemanticArray(
  value: SemanticValue,
): value is readonly SemanticValue[] {
  return Array.isArray(value)
}

function canonicalize(value: SemanticValue): string {
  if (value === null || typeof value === 'boolean' || typeof value === 'string') {
    return JSON.stringify(value)
  }

  if (typeof value === 'number') {
    if (!Number.isFinite(value)) {
      throw new TypeError('Semantic fingerprint accepts only finite numbers.')
    }

    return JSON.stringify(value)
  }

  if (isSemanticArray(value)) {
    return `[${value.map((item) => canonicalize(item)).join(',')}]`
  }

  const keys = Object.keys(value).sort((left, right) =>
    left < right ? -1 : left > right ? 1 : 0,
  )

  return `{${keys
    .map((key) => `${JSON.stringify(key)}:${canonicalize(value[key]!)}`)
    .join(',')}}`
}

export function canonicalizeSemanticInput(value: SemanticValue): string {
  return canonicalize(value)
}

export async function semanticFingerprintSha256(
  value: SemanticValue,
): Promise<string> {
  const encoded = new TextEncoder().encode(canonicalizeSemanticInput(value))
  const digest = await globalThis.crypto.subtle.digest('SHA-256', encoded)

  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, '0'),
  ).join('')
}

export interface RetryPolicy {
  readonly baseSeconds: number
  readonly maxSeconds: number
  readonly jitterPercent: number
}

export function computeRetryDelaySeconds(
  attemptInCycle: number,
  jitterUnit: number,
  policy: RetryPolicy,
): number {
  if (!Number.isInteger(attemptInCycle) || attemptInCycle < 1) {
    throw new TypeError('Retry attempt must be a positive integer.')
  }
  if (!Number.isFinite(jitterUnit) || jitterUnit < 0 || jitterUnit > 1) {
    throw new TypeError('Retry jitter unit must be between zero and one.')
  }
  if (
    !Number.isInteger(policy.baseSeconds) ||
    !Number.isInteger(policy.maxSeconds) ||
    policy.baseSeconds < 1 ||
    policy.maxSeconds < policy.baseSeconds ||
    !Number.isInteger(policy.jitterPercent) ||
    policy.jitterPercent < 0 ||
    policy.jitterPercent > 100
  ) {
    throw new TypeError('Invalid retry policy.')
  }

  const exponential = Math.min(
    policy.maxSeconds,
    policy.baseSeconds * 2 ** (attemptInCycle - 1),
  )
  const jitter = policy.jitterPercent / 100

  return exponential * (1 + jitter * (2 * jitterUnit - 1))
}

const redactedDeliveryError = 'Sensitive worker error details were redacted.'
const credentialAssignmentPattern =
  /(?:^|[?&;\s,])(?:x[-_](?:amz|goog)[-_])?(?:access[_-]?token|refresh[_-]?token|id[_-]?token|api[_-]?key|apikey|authorization|credential|token|signature|sig|secret|password|passwd)\s*[:=]/iu
const rawJwtPattern =
  /(?:^|[^a-z0-9_-])eyj[a-z0-9_-]{4,}\.[a-z0-9_-]{4,}\.[a-z0-9_-]{4,}(?:$|[^a-z0-9_-])/iu
const unsafeErrorPattern =
  /(?:^|[\s:=])bearer\s+[a-z0-9._~+/-]+|service[_-]?role\s*[:=]|postgres(?:ql)?:\/\/|stack[\s_-]?trace/iu

export function sanitizeDeliveryError(message: string): string {
  const normalized = message.trim().replace(/[\r\n\t]+/gu, ' ')
  if (
    normalized.length < 1 ||
    normalized.length > 500
  ) {
    throw new TypeError('Unsafe delivery error.')
  }

  if (
    unsafeErrorPattern.test(normalized) ||
    rawJwtPattern.test(normalized) ||
    credentialAssignmentPattern.test(normalized)
  ) {
    return redactedDeliveryError
  }

  return normalized
}

type EventContract = Readonly<{
  eventType: string
  eventVersion: number
  payloadSchema: z.ZodType
  handler: EventHandler
}>

export interface HandlerRegistry {
  dispatch(
    envelope: OutboxEnvelope,
    context: TechnicalExecutionContext,
  ): Promise<HandlerResult>
}

function eventContractKey(eventType: string, eventVersion: number): string {
  return `${eventType}@${eventVersion}`
}

export function createHandlerRegistry(
  contracts: readonly EventContract[],
): HandlerRegistry {
  const registry = new Map<string, EventContract>()

  for (const contract of contracts) {
    const key = eventContractKey(contract.eventType, contract.eventVersion)
    if (registry.has(key)) {
      throw new Error(`Duplicate event contract: ${key}`)
    }
    registry.set(key, contract)
  }

  return {
    async dispatch(envelope, context) {
      const { event } = envelope
      const contract = registry.get(
        eventContractKey(event.eventType, event.eventVersion),
      )

      if (contract === undefined) {
        return {
          status: 'terminal_failure',
          code: 'EVENT_CONTRACT_UNSUPPORTED',
        }
      }

      if (event.scope.kind !== 'tenant' || event.scope.tenantId !== context.tenantId) {
        return { status: 'terminal_failure', code: 'EVENT_TENANT_MISMATCH' }
      }

      const parsedPayload = contract.payloadSchema.safeParse(event.payload)
      if (!parsedPayload.success) {
        return { status: 'terminal_failure', code: 'EVENT_PAYLOAD_INVALID' }
      }

      const validatedEvent = {
        ...event,
        payload: parsedPayload.data,
      }

      return contract.handler.handle(validatedEvent, {
        ...context,
        capability: contract.handler.capability,
      })
    },
  }
}
