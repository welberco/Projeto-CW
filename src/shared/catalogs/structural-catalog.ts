import { z } from 'zod'

export const catalogStatusSchema = z.enum(['active', 'inactive'])
export type CatalogStatus = z.infer<typeof catalogStatusSchema>

const uuidSchema = z.string().uuid()
const codeSchema = z
  .string()
  .trim()
  .min(1)
  .max(64)
  .regex(/^[A-Za-z0-9][A-Za-z0-9._/-]*$/)
const optionalCodeSchema = codeSchema.nullable()
const nameSchema = z.string().trim().min(1).max(160)
const descriptionSchema = z.string().trim().max(2_000).nullable()
const timestampSchema = z.string().datetime({ offset: true })

export const structuralCatalogResultSchema = z
  .object({
    id: uuidSchema,
    version: z.number().int().positive(),
    status: catalogStatusSchema,
    command_correlation_id: uuidSchema,
  })
  .strict()

export const structuralCatalogLookupSchema = z
  .object({
    id: uuidSchema,
    code: optionalCodeSchema,
    name: nameSchema,
  })
  .strict()

const structuralCatalogAdminBaseSchema = z.object({
  id: uuidSchema,
  name: nameSchema,
  description: descriptionSchema,
  status: catalogStatusSchema,
  version: z.number().int().positive(),
  updated_at: timestampSchema,
})

export const locationTypeListItemSchema = structuralCatalogAdminBaseSchema
  .extend({ code: codeSchema })
  .strict()
export const locationTypeDetailSchema = locationTypeListItemSchema
  .extend({ created_at: timestampSchema })
  .strict()

export const locationListItemSchema = structuralCatalogAdminBaseSchema
  .extend({
    location_type_id: uuidSchema,
    parent_id: uuidSchema.nullable(),
    code: optionalCodeSchema,
  })
  .strict()
export const locationDetailSchema = locationListItemSchema
  .extend({ created_at: timestampSchema })
  .strict()
export const locationChildSchema = z
  .object({
    id: uuidSchema,
    location_type_id: uuidSchema,
    parent_id: uuidSchema.nullable(),
    code: optionalCodeSchema,
    name: nameSchema,
    status: catalogStatusSchema,
    version: z.number().int().positive(),
  })
  .strict()

export const costCenterListItemSchema = structuralCatalogAdminBaseSchema
  .extend({ parent_id: uuidSchema.nullable(), code: codeSchema })
  .strict()
export const costCenterDetailSchema = costCenterListItemSchema
  .extend({ created_at: timestampSchema })
  .strict()
export const costCenterChildSchema = z
  .object({
    id: uuidSchema,
    parent_id: uuidSchema.nullable(),
    code: codeSchema,
    name: nameSchema,
    status: catalogStatusSchema,
    version: z.number().int().positive(),
  })
  .strict()

export const sectorListItemSchema = structuralCatalogAdminBaseSchema
  .extend({ code: optionalCodeSchema })
  .strict()
export const sectorDetailSchema = sectorListItemSchema
  .extend({ created_at: timestampSchema })
  .strict()

export type StructuralCatalogResult = z.infer<typeof structuralCatalogResultSchema>
export type StructuralCatalogLookup = z.infer<typeof structuralCatalogLookupSchema>
export type LocationTypeListItem = z.infer<typeof locationTypeListItemSchema>
export type LocationTypeDetail = z.infer<typeof locationTypeDetailSchema>
export type LocationListItem = z.infer<typeof locationListItemSchema>
export type LocationDetail = z.infer<typeof locationDetailSchema>
export type LocationChild = z.infer<typeof locationChildSchema>
export type CostCenterListItem = z.infer<typeof costCenterListItemSchema>
export type CostCenterDetail = z.infer<typeof costCenterDetailSchema>
export type CostCenterChild = z.infer<typeof costCenterChildSchema>
export type SectorListItem = z.infer<typeof sectorListItemSchema>
export type SectorDetail = z.infer<typeof sectorDetailSchema>

export const locationTypeInputSchema = z
  .object({ code: codeSchema, name: nameSchema, description: descriptionSchema })
  .strict()

export const locationInputSchema = z
  .object({
    locationTypeId: uuidSchema,
    parentId: uuidSchema.nullable(),
    code: optionalCodeSchema,
    name: nameSchema,
    description: descriptionSchema,
  })
  .strict()

export const costCenterInputSchema = z
  .object({
    parentId: uuidSchema.nullable(),
    code: codeSchema,
    name: nameSchema,
    description: descriptionSchema,
  })
  .strict()

export const sectorInputSchema = z
  .object({ code: optionalCodeSchema, name: nameSchema, description: descriptionSchema })
  .strict()

export const structuralCatalogCommandContextSchema = z
  .object({
    reason: z.string().trim().min(1).max(500),
    correlationId: uuidSchema,
    idempotencyKey: z
      .string()
      .min(8)
      .max(200)
      .regex(/^[A-Za-z0-9][A-Za-z0-9._:-]*$/),
  })
  .strict()

export type StructuralCatalogResource =
  | 'location_types'
  | 'locations'
  | 'cost_centers'
  | 'sectors'

export interface StructuralCatalogSemanticInput {
  readonly resource: StructuralCatalogResource
  readonly action: 'create' | 'update' | 'move' | 'inactivate' | 'reactivate'
  readonly id?: string
  readonly expectedVersion?: number
  readonly code?: string | null
  readonly name?: string
  readonly description?: string | null
  readonly parentId?: string | null
  readonly locationTypeId?: string
}

export function structuralCatalogQueryKey(
  tenantId: string,
  resource: StructuralCatalogResource,
  projection: 'admin' | 'lookup',
  filters: Readonly<Record<string, string | number | null>> = {},
): readonly unknown[] {
  return ['tenant', tenantId, 'catalog', resource, projection, filters] as const
}

export const w4aEventTypes = [
  'cadastros.location_type.created',
  'cadastros.location_type.updated',
  'cadastros.location_type.inactivated',
  'cadastros.location_type.reactivated',
  'cadastros.location.created',
  'cadastros.location.updated',
  'cadastros.location.moved',
  'cadastros.location.inactivated',
  'cadastros.location.reactivated',
  'cadastros.cost_center.created',
  'cadastros.cost_center.updated',
  'cadastros.cost_center.moved',
  'cadastros.cost_center.inactivated',
  'cadastros.cost_center.reactivated',
  'cadastros.sector.created',
  'cadastros.sector.updated',
  'cadastros.sector.inactivated',
  'cadastros.sector.reactivated',
] as const
