import type { PublicConfig } from '@/app/config/public-config'

export interface ReleaseIdentity {
  environment: PublicConfig['appEnvironment']
  releaseId: string
}

export function createReleaseIdentity(config: PublicConfig): ReleaseIdentity {
  return Object.freeze({
    environment: config.appEnvironment,
    releaseId: config.releaseId,
  })
}

export function createUnconfiguredLocalReleaseIdentity(): ReleaseIdentity {
  return Object.freeze({
    environment: 'local',
    releaseId: 'local-unconfigured',
  })
}
