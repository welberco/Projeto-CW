export type ReleaseEnvironment = 'local' | 'test' | 'staging' | 'production'

export interface ReleaseIdentity {
  environment: ReleaseEnvironment
  releaseId: string
}

interface ReleaseConfig {
  appEnvironment: ReleaseEnvironment
  releaseId: string
}

export function createReleaseIdentity(config: ReleaseConfig): ReleaseIdentity {
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
