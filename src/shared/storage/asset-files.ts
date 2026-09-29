import { z } from 'zod'

export const assetFilePermissionCodes = [
  'shared.asset_files.read.all_tenant',
  'shared.asset_files.reserve.all_tenant',
  'shared.asset_files.finalize.all_tenant',
  'shared.asset_files.delete.all_tenant',
  'shared.asset_files.retry.all_tenant',
] as const

export const assetFileClassSchema = z.enum(['asset_image', 'asset_document'])

export const assetFileLogicalStatusSchema = z.enum([
  'RESERVED',
  'PENDING_PROCESSING',
  'PROCESSING',
  'AVAILABLE',
  'REJECTED',
  'FAILED',
  'EXPIRED',
  'DELETED',
])

export const assetFilePhysicalStatusSchema = z.enum([
  'EXPECTED',
  'PRESENT',
  'DELETE_PENDING',
  'ABSENT',
  'DELETE_FAILED',
])

export const assetFileFenceSchema = z.number().int().positive()

export const assetFilePublicStateSchema = z
  .object({
    id: z.string().uuid(),
    asset_id: z.string().uuid(),
    file_class: assetFileClassSchema,
    logical_status: assetFileLogicalStatusSchema,
    version: z.number().int().positive(),
  })
  .strict()

export type AssetFilePermissionCode = (typeof assetFilePermissionCodes)[number]
export type AssetFileClass = z.infer<typeof assetFileClassSchema>
export type AssetFileLogicalStatus = z.infer<typeof assetFileLogicalStatusSchema>
export type AssetFilePhysicalStatus = z.infer<typeof assetFilePhysicalStatusSchema>
export type AssetFilePublicState = z.infer<typeof assetFilePublicStateSchema>
