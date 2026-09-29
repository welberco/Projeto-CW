import { z } from 'zod'

export const assetPermissionCodes = [
  'shared.asset_types.read.all_tenant',
  'shared.asset_types.lookup.all_tenant',
  'shared.asset_types.create.all_tenant',
  'shared.asset_types.update.all_tenant',
  'shared.asset_types.inactivate.all_tenant',
  'shared.asset_types.reactivate.all_tenant',
  'shared.assets.read.all_tenant',
  'shared.assets.lookup.all_tenant',
  'shared.assets.create.all_tenant',
  'shared.assets.update.all_tenant',
  'shared.assets.move.all_tenant',
  'shared.assets.inactivate.all_tenant',
  'shared.assets.reactivate.all_tenant',
  'shared.assets.decommission.all_tenant',
] as const

export const assetRegistrationStatusSchema = z.enum([
  'ACTIVE',
  'INACTIVE',
  'DECOMMISSIONED',
])

export const assetOperationalConditionSchema = z.enum([
  'OPERATIONAL',
  'PARTIAL',
  'UNDER_MAINTENANCE',
  'OUT_OF_OPERATION',
])

export const assetSpecificationFieldTypeSchema = z.enum([
  'STRING',
  'INTEGER',
  'DECIMAL',
  'BOOLEAN',
  'DATE',
  'ENUM',
])

const uuidSchema = z.string().uuid()
const specificationKeySchema = z
  .string()
  .min(1)
  .max(64)
  .regex(/^[A-Za-z][A-Za-z0-9_]*$/)

export const assetSpecificationFieldSchema = z
  .object({
    key: specificationKeySchema,
    label: z.string().trim().min(1).max(160),
    type: assetSpecificationFieldTypeSchema,
    required: z.boolean(),
    nullable: z.boolean(),
    min_length: z.number().int().nonnegative().optional(),
    max_length: z.number().int().nonnegative().optional(),
    pattern: z
      .string()
      .trim()
      .regex(/^[A-Z][A-Z0-9_]{0,63}$/)
      .optional(),
    minimum: z.number().finite().optional(),
    maximum: z.number().finite().optional(),
    options: z.array(z.string().trim().min(1).max(160)).min(1).optional(),
  })
  .strict()
  .superRefine((field, context) => {
    const hasStringConstraint =
      field.min_length !== undefined ||
      field.max_length !== undefined ||
      field.pattern !== undefined
    const hasNumberConstraint =
      field.minimum !== undefined || field.maximum !== undefined

    if (field.type !== 'STRING' && hasStringConstraint) {
      context.addIssue({
        code: 'custom',
        message: 'String constraints require a STRING field.',
      })
    }
    if (!['INTEGER', 'DECIMAL'].includes(field.type) && hasNumberConstraint) {
      context.addIssue({
        code: 'custom',
        message: 'Numeric constraints require an INTEGER or DECIMAL field.',
      })
    }
    if (field.type !== 'ENUM' && field.options !== undefined) {
      context.addIssue({
        code: 'custom',
        message: 'Options require an ENUM field.',
      })
    }
    if (field.type === 'ENUM' && field.options === undefined) {
      context.addIssue({ code: 'custom', message: 'ENUM fields require options.' })
    }
    if (
      field.options !== undefined &&
      new Set(field.options).size !== field.options.length
    ) {
      context.addIssue({ code: 'custom', message: 'ENUM options must be unique.' })
    }
    if (
      field.min_length !== undefined &&
      field.max_length !== undefined &&
      field.min_length > field.max_length
    ) {
      context.addIssue({ code: 'custom', message: 'Invalid string range.' })
    }
    if (
      field.minimum !== undefined &&
      field.maximum !== undefined &&
      field.minimum > field.maximum
    ) {
      context.addIssue({ code: 'custom', message: 'Invalid numeric range.' })
    }
  })

export const assetSpecificationDefinitionSchema = z
  .object({
    definition_schema_version: z.literal(1),
    asset_type_id: uuidSchema,
    revision: z.number().int().positive(),
    fields: z.array(assetSpecificationFieldSchema).max(200),
  })
  .strict()
  .superRefine((definition, context) => {
    const keys = definition.fields.map((field) => field.key)
    if (new Set(keys).size !== keys.length) {
      context.addIssue({
        code: 'custom',
        path: ['fields'],
        message: 'Specification field keys must be unique.',
      })
    }
  })

export const assetLookupSchema = z
  .object({
    id: uuidSchema,
    code: z.string().trim().min(1).max(64),
    name: z.string().trim().min(1).max(160),
    registration_status: assetRegistrationStatusSchema,
    operational_condition: assetOperationalConditionSchema,
  })
  .strict()

export const assetTypeLookupSchema = z
  .object({
    id: uuidSchema,
    name: z.string().trim().min(1).max(160),
  })
  .strict()

export type AssetPermissionCode = (typeof assetPermissionCodes)[number]
export type AssetRegistrationStatus = z.infer<typeof assetRegistrationStatusSchema>
export type AssetOperationalCondition = z.infer<typeof assetOperationalConditionSchema>
export type AssetSpecificationFieldType = z.infer<typeof assetSpecificationFieldTypeSchema>
export type AssetSpecificationDefinition = z.infer<typeof assetSpecificationDefinitionSchema>
export type AssetLookup = z.infer<typeof assetLookupSchema>
export type AssetTypeLookup = z.infer<typeof assetTypeLookupSchema>
