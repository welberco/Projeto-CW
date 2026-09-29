import { describe, expect, it } from 'vitest'

import {
  assetFileClassSchema,
  assetFileFenceSchema,
  assetFileLogicalStatusSchema,
  assetFilePermissionCodes,
  assetFilePhysicalStatusSchema,
  assetFilePublicStateSchema,
} from './asset-files'

describe('W5A Asset File contracts', () => {
  it('freezes exactly five Asset File permissions', () => {
    expect(assetFilePermissionCodes).toEqual([
      'shared.asset_files.read.all_tenant',
      'shared.asset_files.reserve.all_tenant',
      'shared.asset_files.finalize.all_tenant',
      'shared.asset_files.delete.all_tenant',
      'shared.asset_files.retry.all_tenant',
    ])
    expect(new Set(assetFilePermissionCodes).size).toBe(5)
  })

  it('freezes the two W5 file classes and lifecycle vocabularies', () => {
    expect(assetFileClassSchema.options).toEqual(['asset_image', 'asset_document'])
    expect(assetFileLogicalStatusSchema.options).toEqual([
      'RESERVED',
      'PENDING_PROCESSING',
      'PROCESSING',
      'AVAILABLE',
      'REJECTED',
      'FAILED',
      'EXPIRED',
      'DELETED',
    ])
    expect(assetFilePhysicalStatusSchema.options).toEqual([
      'EXPECTED',
      'PRESENT',
      'DELETE_PENDING',
      'ABSENT',
      'DELETE_FAILED',
    ])
    expect(assetFileFenceSchema.safeParse(1).success).toBe(true)
    expect(assetFileFenceSchema.safeParse(0).success).toBe(false)
  })

  it('keeps secrets, signed URLs and physical keys out of the public state', () => {
    const publicState = {
      id: '10000000-0000-4000-8000-000000000001',
      asset_id: '10000000-0000-4000-8000-000000000002',
      file_class: 'asset_image',
      logical_status: 'PROCESSING',
      version: 1,
    }

    expect(assetFilePublicStateSchema.parse(publicState)).toEqual(publicState)
    for (const forbidden of [
      'signed_upload_token',
      'signed_url',
      'service_role',
      'bucket_credential',
      'storage_key',
      'physical_key',
      'fence',
    ]) {
      expect(
        assetFilePublicStateSchema.safeParse({ ...publicState, [forbidden]: 'secret' }).success,
      ).toBe(false)
    }
  })
})
