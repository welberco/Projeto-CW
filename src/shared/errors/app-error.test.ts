import { describe, expect, it } from 'vitest'
import {
  AppError,
  normalizeAppError,
  toSafeErrorDetails,
} from '@/shared/errors/app-error'

describe('AppError', () => {
  it('keeps provider details out of the user-safe projection', () => {
    const providerDetail = 'token=provider-secret-value'
    const error = normalizeAppError(new Error(providerDetail), 'correlation-test')

    expect(toSafeErrorDetails(error)).toEqual({
      code: 'APP_UNEXPECTED',
      category: 'internal',
      message: 'Não foi possível concluir esta operação com segurança.',
      correlationId: 'correlation-test',
    })
    expect(JSON.stringify(toSafeErrorDetails(error))).not.toContain(providerDetail)
  })

  it('adds correlation without replacing a stable foundational code', () => {
    const error = normalizeAppError(
      new AppError({
        code: 'APP_CONFIG_INVALID',
        category: 'internal',
        userMessage: 'Configuração inválida.',
      }),
      'correlation-test',
    )

    expect(error.code).toBe('APP_CONFIG_INVALID')
    expect(error.correlationId).toBe('correlation-test')
  })
})
