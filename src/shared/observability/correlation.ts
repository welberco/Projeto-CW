declare const correlationIdBrand: unique symbol

export type ClientCorrelationId = string & {
  readonly [correlationIdBrand]: 'client-correlation-id'
}

const unavailableCorrelationId =
  'client-correlation-unavailable' as ClientCorrelationId

export function createClientCorrelationId(): ClientCorrelationId {
  if (typeof globalThis.crypto?.randomUUID === 'function') {
    return globalThis.crypto.randomUUID() as ClientCorrelationId
  }

  return unavailableCorrelationId
}

export function createCorrelationSuggestionHeaders(
  correlationId: ClientCorrelationId,
): Readonly<Record<string, string>> {
  return { 'x-client-correlation-id': correlationId }
}
