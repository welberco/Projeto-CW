export type AppErrorCategory =
  | 'validation'
  | 'unauthenticated'
  | 'forbidden'
  | 'not_found'
  | 'conflict'
  | 'invalid_state'
  | 'limit'
  | 'unavailable'
  | 'rate_limit'
  | 'internal'

type TechnicalDetails = Readonly<Record<string, unknown>>

interface AppErrorOptions {
  code: string
  category: AppErrorCategory
  userMessage: string
  correlationId?: string
  technicalDetails?: TechnicalDetails
  cause?: unknown
}

export interface SafeErrorDetails {
  code: string
  category: AppErrorCategory
  message: string
  correlationId?: string
}

export class AppError extends Error {
  readonly code: string
  readonly category: AppErrorCategory
  readonly correlationId: string | undefined
  readonly technicalDetails: TechnicalDetails | undefined

  constructor(options: AppErrorOptions) {
    super(options.userMessage, { cause: options.cause })
    this.name = 'AppError'
    this.code = options.code
    this.category = options.category
    this.correlationId = options.correlationId
    this.technicalDetails = options.technicalDetails
  }
}

export function normalizeAppError(
  error: unknown,
  correlationId?: string,
): AppError {
  if (error instanceof AppError) {
    if (error.correlationId !== undefined || correlationId === undefined) {
      return error
    }

    return new AppError({
      code: error.code,
      category: error.category,
      userMessage: error.message,
      correlationId,
      ...(error.technicalDetails === undefined
        ? {}
        : { technicalDetails: error.technicalDetails }),
      cause: error.cause,
    })
  }

  return new AppError({
    code: 'APP_UNEXPECTED',
    category: 'internal',
    userMessage: 'Não foi possível concluir esta operação com segurança.',
    ...(correlationId === undefined ? {} : { correlationId }),
    cause: error,
  })
}

export function toSafeErrorDetails(error: AppError): SafeErrorDetails {
  return {
    code: error.code,
    category: error.category,
    message: error.message,
    ...(error.correlationId === undefined
      ? {}
      : { correlationId: error.correlationId }),
  }
}
