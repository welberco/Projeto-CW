import { z } from 'zod'
import { AppError } from '@/shared/errors/app-error'

const appEnvironmentSchema = z.enum([
  'local',
  'test',
  'staging',
  'production',
])

function decodesToPrivilegedSupabaseRole(value: string): boolean {
  if (/^sb_secret_/iu.test(value) || value.toLowerCase().includes('service_role')) {
    return true
  }

  const payload = value.split('.')[1]

  if (payload === undefined || typeof globalThis.atob !== 'function') {
    return false
  }

  try {
    const normalizedPayload = payload.replaceAll('-', '+').replaceAll('_', '/')
    const paddedPayload = normalizedPayload.padEnd(
      Math.ceil(normalizedPayload.length / 4) * 4,
      '=',
    )
    const claims: unknown = JSON.parse(globalThis.atob(paddedPayload))

    return (
      typeof claims === 'object' &&
      claims !== null &&
      'role' in claims &&
      claims.role === 'service_role'
    )
  } catch {
    return false
  }
}

const publicConfigSchema = z.object({
  VITE_SUPABASE_URL: z
    .string()
    .trim()
    .url()
    .refine((value) => value.startsWith('https://') || value.startsWith('http://'), {
      message: 'must use HTTP or HTTPS',
    }),
  VITE_SUPABASE_ANON_KEY: z
    .string()
    .trim()
    .min(20)
    .max(4096)
    .refine((value) => !decodesToPrivilegedSupabaseRole(value), {
      message: 'must be a public browser key',
    }),
  VITE_APP_ENV: appEnvironmentSchema.default('local'),
  VITE_RELEASE_ID: z.string().trim().min(1).max(128).optional(),
})

export interface PublicConfig {
  supabaseUrl: string
  supabaseAnonKey: string
  appEnvironment: z.infer<typeof appEnvironmentSchema>
  releaseId: string
}

export function parsePublicConfig(
  source: Readonly<Record<string, unknown>>,
): PublicConfig {
  const result = publicConfigSchema.safeParse(source)

  if (!result.success) {
    throw new AppError({
      code: 'APP_CONFIG_INVALID',
      category: 'internal',
      userMessage: 'A configuração pública da aplicação está ausente ou inválida.',
      technicalDetails: {
        fields: result.error.issues.map((issue) => issue.path.join('.')),
      },
    })
  }

  const { VITE_APP_ENV: appEnvironment, VITE_RELEASE_ID: releaseId } =
    result.data

  if (
    releaseId === undefined &&
    (appEnvironment === 'staging' || appEnvironment === 'production')
  ) {
    throw new AppError({
      code: 'APP_RELEASE_ID_REQUIRED',
      category: 'internal',
      userMessage: 'A identidade pública desta release não foi configurada.',
      technicalDetails: { fields: ['VITE_RELEASE_ID'] },
    })
  }

  return Object.freeze({
    supabaseUrl: result.data.VITE_SUPABASE_URL,
    supabaseAnonKey: result.data.VITE_SUPABASE_ANON_KEY,
    appEnvironment,
    releaseId: releaseId ?? `${appEnvironment}-dev`,
  })
}
