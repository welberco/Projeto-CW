import { describe, expect, it } from 'vitest'
import { AppError, toSafeErrorDetails } from '@/shared/errors/app-error'
import { parsePublicConfig } from '@/app/config/public-config'
import { publicTestEnvironment } from '@/test/public-test-environment'

const validLocalConfig = {
  ...publicTestEnvironment,
  VITE_APP_ENV: 'local',
  VITE_RELEASE_ID: undefined,
}

describe('parsePublicConfig', () => {
  it('validates public config and applies an explicit local release fallback', () => {
    expect(parsePublicConfig(validLocalConfig)).toEqual({
      supabaseUrl: 'http://127.0.0.1:54331',
      supabaseAnonKey: 'public-local-test-placeholder',
      appEnvironment: 'local',
      releaseId: 'local-dev',
    })
  })

  it('fails safely without echoing an invalid credential', () => {
    const invalidCredential = 'secret'

    try {
      parsePublicConfig({
        ...validLocalConfig,
        VITE_SUPABASE_ANON_KEY: invalidCredential,
      })
      throw new Error('Expected config parsing to fail.')
    } catch (error) {
      expect(error).toBeInstanceOf(AppError)
      const safeError = toSafeErrorDetails(error as AppError)
      expect(JSON.stringify(safeError)).not.toContain(invalidCredential)
      expect(safeError.code).toBe('APP_CONFIG_INVALID')
    }
  })

  it('requires a release identity in staging and production', () => {
    expect(() =>
      parsePublicConfig({
        ...validLocalConfig,
        VITE_APP_ENV: 'production',
      }),
    ).toThrowError(AppError)
  })
})
