import { toSafeErrorDetails, type AppError } from '@/shared/errors/app-error'
import type { ReleaseIdentity } from '@/shared/observability/release'

export function logSafeError(
  error: AppError,
  release: ReleaseIdentity,
): void {
  console.error('[cw-v2:error]', {
    ...toSafeErrorDetails(error),
    environment: release.environment,
    releaseId: release.releaseId,
  })
}
