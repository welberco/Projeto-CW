import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  createClientCorrelationId,
  createCorrelationSuggestionHeaders,
} from '@/shared/observability/correlation'

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('client correlation', () => {
  it('creates a client suggestion without presenting it as authority', () => {
    vi.stubGlobal('crypto', { randomUUID: () => 'local-correlation-id' })

    const correlationId = createClientCorrelationId()

    expect(createCorrelationSuggestionHeaders(correlationId)).toEqual({
      'x-client-correlation-id': 'local-correlation-id',
    })
  })

  it('uses a safe deterministic fallback when randomUUID is unavailable', () => {
    vi.stubGlobal('crypto', {})

    expect(createClientCorrelationId()).toBe('client-correlation-unavailable')
  })
})
