import { z } from 'zod'

export const maintenanceCatalogStatusSchema = z.enum(['active', 'inactive'])
export const maintenanceReasonContextSchema = z.enum([
  'CANCEL_REQUEST',
  'REJECT_REQUEST',
  'PAUSE_WORK_ORDER',
  'CANCEL_WORK_ORDER',
  'RETURN_WORK_ORDER',
])
export const checklistResponseTypeSchema = z.enum([
  'DONE_NOT_DONE',
  'CONFORMING_NONCONFORMING',
  'YES_NO',
  'TEXT',
  'NUMBER',
  'OBSERVATION',
])

const uuidSchema = z.string().uuid()
const versionSchema = z.number().int().positive()
const timestampSchema = z.string().datetime({ offset: true })
const codeSchema = z.string().trim().min(1).max(64).regex(/^[A-Za-z0-9][A-Za-z0-9._/-]*$/)
const nullableCodeSchema = codeSchema.nullable()
const nameSchema = z.string().trim().min(1).max(160)
const descriptionSchema = z.string().trim().max(2_000).nullable()
const reasonSchema = z.string().trim().min(1).max(500)
const idempotencyKeySchema = z.string().min(8).max(200).regex(/^[A-Za-z0-9][A-Za-z0-9._:-]*$/)
const searchTextSchema = z.string().trim().max(160).nullable().optional()
const limitSchema = z.number().int().min(1).max(100).optional()
const offsetSchema = z.number().int().nonnegative().optional()

export const maintenanceCatalogCommandResultSchema = z.object({
  id: uuidSchema,
  version: versionSchema,
  status: maintenanceCatalogStatusSchema,
  command_correlation_id: uuidSchema,
}).strict()

export const catalogTemplateApplyResultSchema = z.object({
  id: uuidSchema,
  version: versionSchema,
  status: z.literal('applied'),
  command_correlation_id: uuidSchema,
  template_key: z.literal('cw_maintenance_taxonomy'),
  template_version: z.literal(1),
  category_ids: z.array(uuidSchema).length(11),
  subcategory_ids: z.array(uuidSchema).length(39),
  category_count: z.literal(11),
  subcategory_count: z.literal(39),
}).strict()

const catalogListBaseSchema = z.object({
  id: uuidSchema,
  code: nullableCodeSchema,
  name: nameSchema,
  description: descriptionSchema,
  status: maintenanceCatalogStatusSchema,
  version: versionSchema,
  updated_at: timestampSchema,
})

export const maintenanceCategoryListItemSchema = catalogListBaseSchema.strict()
export const maintenanceCategorySchema = catalogListBaseSchema.extend({ created_at: timestampSchema }).strict()
export const maintenanceCategoryLookupSchema = z.object({
  id: uuidSchema,
  code: nullableCodeSchema,
  name: nameSchema,
}).strict()

export const maintenanceSubcategoryListItemSchema = catalogListBaseSchema.extend({
  category_id: uuidSchema,
}).strict()
export const maintenanceSubcategorySchema = maintenanceSubcategoryListItemSchema.extend({
  created_at: timestampSchema,
}).strict()
export const maintenanceSubcategoryLookupSchema = maintenanceCategoryLookupSchema

const maintenanceReasonBaseSchema = catalogListBaseSchema.extend({
  usage_context: maintenanceReasonContextSchema,
})
export const maintenanceReasonListItemSchema = maintenanceReasonBaseSchema.strict()
export const maintenanceReasonSchema = maintenanceReasonBaseSchema.extend({ created_at: timestampSchema }).strict()
export const maintenanceReasonLookupSchema = maintenanceCategoryLookupSchema

export const documentTypeListItemSchema = catalogListBaseSchema.strict()
export const documentTypeSchema = documentTypeListItemSchema.extend({ created_at: timestampSchema }).strict()
export const documentTypeLookupSchema = maintenanceCategoryLookupSchema

export const checklistTemplateItemSchema = z.object({
  id: uuidSchema,
  position: z.number().int().min(1).max(10_000),
  prompt: z.string().trim().min(1).max(500),
  response_type: checklistResponseTypeSchema,
  required: z.boolean(),
  instructions: z.string().trim().max(2_000).nullable(),
}).strict()

export const checklistTemplateItemInputSchema = checklistTemplateItemSchema
  .omit({ id: true })
  .strict()

export const checklistTemplateListItemSchema = catalogListBaseSchema.extend({
  category_id: uuidSchema,
  item_count: z.number().int().nonnegative(),
}).strict()
export const checklistTemplateSchema = catalogListBaseSchema.extend({
  category_id: uuidSchema,
  items: z.array(checklistTemplateItemSchema).min(1).max(200),
  created_at: timestampSchema,
}).strict().superRefine((template, context) => {
  const positions = template.items.map((item) => item.position)
  if (new Set(positions).size !== positions.length) {
    context.addIssue({ code: 'custom', path: ['items'], message: 'Checklist item positions must be unique.' })
  }
  if (positions.some((position, index) => index > 0 && position <= positions[index - 1]!)) {
    context.addIssue({ code: 'custom', path: ['items'], message: 'Checklist items must be ordered by position.' })
  }
})
export const checklistTemplateLookupSchema = z.object({
  id: uuidSchema,
  category_id: uuidSchema,
  code: nullableCodeSchema,
  name: nameSchema,
}).strict()

const templatePreviewSubcategorySchema = z.object({
  key: z.string().min(1).max(120),
  code: z.string().min(1).max(64),
  name: nameSchema,
}).strict()
const templatePreviewCategorySchema = templatePreviewSubcategorySchema.extend({
  subcategories: z.array(templatePreviewSubcategorySchema),
}).strict()
export const catalogTemplatePreviewSchema = z.object({
  template_key: z.literal('cw_maintenance_taxonomy'),
  template_version: z.literal(1),
  category_count: z.literal(11),
  subcategory_count: z.literal(39),
  categories: z.array(templatePreviewCategorySchema).length(11),
}).strict()

export const maintenanceCatalogCommandContextSchema = z.object({
  reason: reasonSchema,
  correlationId: uuidSchema,
  idempotencyKey: idempotencyKeySchema,
}).strict()
const versionedCommandSchema = z.object({
  id: uuidSchema,
  expectedVersion: versionSchema,
  ...maintenanceCatalogCommandContextSchema.shape,
})
const catalogDefinitionSchema = z.object({
  code: nullableCodeSchema,
  name: nameSchema,
  description: descriptionSchema,
})
const reasonDefinitionSchema = catalogDefinitionSchema.extend({ code: codeSchema })

export const createMaintenanceCategoryInputSchema = catalogDefinitionSchema.extend({
  ...maintenanceCatalogCommandContextSchema.shape,
}).strict()
export const updateMaintenanceCategoryInputSchema = catalogDefinitionSchema.extend({
  ...versionedCommandSchema.shape,
}).strict()
export const maintenanceCategoryStatusCommandInputSchema = versionedCommandSchema.strict()

export const createMaintenanceSubcategoryInputSchema = catalogDefinitionSchema.extend({
  categoryId: uuidSchema,
  ...maintenanceCatalogCommandContextSchema.shape,
}).strict()
export const updateMaintenanceSubcategoryInputSchema = catalogDefinitionSchema.extend({
  categoryId: uuidSchema,
  ...versionedCommandSchema.shape,
}).strict()
export const maintenanceSubcategoryStatusCommandInputSchema = versionedCommandSchema.strict()

export const applyCatalogTemplateInputSchema = z.object({
  templateKey: z.literal('cw_maintenance_taxonomy'),
  templateVersion: z.literal(1),
  ...maintenanceCatalogCommandContextSchema.shape,
}).strict()

export const createMaintenanceReasonInputSchema = reasonDefinitionSchema.extend({
  usageContext: maintenanceReasonContextSchema,
  ...maintenanceCatalogCommandContextSchema.shape,
}).strict()
export const updateMaintenanceReasonInputSchema = reasonDefinitionSchema.extend({
  ...versionedCommandSchema.shape,
}).strict()
export const maintenanceReasonStatusCommandInputSchema = versionedCommandSchema.strict()

export const createDocumentTypeInputSchema = catalogDefinitionSchema.extend({
  ...maintenanceCatalogCommandContextSchema.shape,
}).strict()
export const updateDocumentTypeInputSchema = catalogDefinitionSchema.extend({
  ...versionedCommandSchema.shape,
}).strict()
export const documentTypeStatusCommandInputSchema = versionedCommandSchema.strict()

const checklistDefinitionInputSchema = catalogDefinitionSchema.extend({
  categoryId: uuidSchema,
  items: z.array(checklistTemplateItemInputSchema).min(1).max(200).superRefine((items, context) => {
    const positions = items.map((item) => item.position)
    if (new Set(positions).size !== positions.length) {
      context.addIssue({ code: 'custom', message: 'Checklist item positions must be unique.' })
    }
  }),
})
export const createChecklistTemplateInputSchema = checklistDefinitionInputSchema.extend({
  ...maintenanceCatalogCommandContextSchema.shape,
}).strict()
export const updateChecklistTemplateDefinitionInputSchema = checklistDefinitionInputSchema.extend({
  ...versionedCommandSchema.shape,
}).strict()
export const checklistTemplateStatusCommandInputSchema = versionedCommandSchema.strict()

const listInputSchema = z.object({
  searchText: searchTextSchema,
  status: maintenanceCatalogStatusSchema.nullable().optional(),
  limit: limitSchema,
  offset: offsetSchema,
}).strict()
export const maintenanceCategoryListInputSchema = listInputSchema
export const maintenanceSubcategoryListInputSchema = listInputSchema.extend({ categoryId: uuidSchema.nullable().optional() }).strict()
export const maintenanceReasonListInputSchema = listInputSchema.extend({ usageContext: maintenanceReasonContextSchema.nullable().optional() }).strict()
export const documentTypeListInputSchema = listInputSchema
export const checklistTemplateListInputSchema = listInputSchema.extend({ categoryId: uuidSchema.nullable().optional() }).strict()

const lookupInputSchema = z.object({ searchText: searchTextSchema, limit: limitSchema }).strict()
export const maintenanceCategoryLookupInputSchema = lookupInputSchema
export const maintenanceSubcategoryLookupInputSchema = lookupInputSchema.extend({ categoryId: uuidSchema.nullable().optional() }).strict()
export const maintenanceReasonLookupInputSchema = lookupInputSchema.extend({ usageContext: maintenanceReasonContextSchema }).strict()
export const documentTypeLookupInputSchema = lookupInputSchema
export const checklistTemplateLookupInputSchema = lookupInputSchema.extend({ categoryId: uuidSchema.nullable().optional() }).strict()
export const maintenanceCatalogIdSchema = uuidSchema
export const catalogTemplatePreviewInputSchema = z.object({
  templateKey: z.literal('cw_maintenance_taxonomy').optional(),
  templateVersion: z.literal(1).optional(),
}).strict()

export type MaintenanceCatalogStatus = z.infer<typeof maintenanceCatalogStatusSchema>
export type MaintenanceReasonContext = z.infer<typeof maintenanceReasonContextSchema>
export type ChecklistResponseType = z.infer<typeof checklistResponseTypeSchema>
export type MaintenanceCatalogCommandResult = z.infer<typeof maintenanceCatalogCommandResultSchema>
export type CatalogTemplateApplyResult = z.infer<typeof catalogTemplateApplyResultSchema>
export type MaintenanceCategory = z.infer<typeof maintenanceCategorySchema>
export type MaintenanceCategoryListItem = z.infer<typeof maintenanceCategoryListItemSchema>
export type MaintenanceCategoryLookup = z.infer<typeof maintenanceCategoryLookupSchema>
export type MaintenanceSubcategory = z.infer<typeof maintenanceSubcategorySchema>
export type MaintenanceSubcategoryListItem = z.infer<typeof maintenanceSubcategoryListItemSchema>
export type MaintenanceSubcategoryLookup = z.infer<typeof maintenanceSubcategoryLookupSchema>
export type MaintenanceReason = z.infer<typeof maintenanceReasonSchema>
export type MaintenanceReasonListItem = z.infer<typeof maintenanceReasonListItemSchema>
export type MaintenanceReasonLookup = z.infer<typeof maintenanceReasonLookupSchema>
export type DocumentType = z.infer<typeof documentTypeSchema>
export type DocumentTypeListItem = z.infer<typeof documentTypeListItemSchema>
export type DocumentTypeLookup = z.infer<typeof documentTypeLookupSchema>
export type ChecklistTemplate = z.infer<typeof checklistTemplateSchema>
export type ChecklistTemplateListItem = z.infer<typeof checklistTemplateListItemSchema>
export type ChecklistTemplateItem = z.infer<typeof checklistTemplateItemSchema>
export type ChecklistTemplateLookup = z.infer<typeof checklistTemplateLookupSchema>
export type CatalogTemplatePreview = z.infer<typeof catalogTemplatePreviewSchema>
export type CreateMaintenanceCategoryInput = z.infer<typeof createMaintenanceCategoryInputSchema>
export type UpdateMaintenanceCategoryInput = z.infer<typeof updateMaintenanceCategoryInputSchema>
export type MaintenanceCategoryStatusCommandInput = z.infer<typeof maintenanceCategoryStatusCommandInputSchema>
export type CreateMaintenanceSubcategoryInput = z.infer<typeof createMaintenanceSubcategoryInputSchema>
export type UpdateMaintenanceSubcategoryInput = z.infer<typeof updateMaintenanceSubcategoryInputSchema>
export type MaintenanceSubcategoryStatusCommandInput = z.infer<typeof maintenanceSubcategoryStatusCommandInputSchema>
export type ApplyCatalogTemplateInput = z.infer<typeof applyCatalogTemplateInputSchema>
export type CreateMaintenanceReasonInput = z.infer<typeof createMaintenanceReasonInputSchema>
export type UpdateMaintenanceReasonInput = z.infer<typeof updateMaintenanceReasonInputSchema>
export type MaintenanceReasonStatusCommandInput = z.infer<typeof maintenanceReasonStatusCommandInputSchema>
export type CreateDocumentTypeInput = z.infer<typeof createDocumentTypeInputSchema>
export type UpdateDocumentTypeInput = z.infer<typeof updateDocumentTypeInputSchema>
export type DocumentTypeStatusCommandInput = z.infer<typeof documentTypeStatusCommandInputSchema>
export type CreateChecklistTemplateInput = z.infer<typeof createChecklistTemplateInputSchema>
export type UpdateChecklistTemplateDefinitionInput = z.infer<typeof updateChecklistTemplateDefinitionInputSchema>
export type ChecklistTemplateStatusCommandInput = z.infer<typeof checklistTemplateStatusCommandInputSchema>
export type MaintenanceCategoryListInput = z.infer<typeof maintenanceCategoryListInputSchema>
export type MaintenanceSubcategoryListInput = z.infer<typeof maintenanceSubcategoryListInputSchema>
export type MaintenanceReasonListInput = z.infer<typeof maintenanceReasonListInputSchema>
export type DocumentTypeListInput = z.infer<typeof documentTypeListInputSchema>
export type ChecklistTemplateListInput = z.infer<typeof checklistTemplateListInputSchema>
export type MaintenanceCategoryLookupInput = z.infer<typeof maintenanceCategoryLookupInputSchema>
export type MaintenanceSubcategoryLookupInput = z.infer<typeof maintenanceSubcategoryLookupInputSchema>
export type MaintenanceReasonLookupInput = z.infer<typeof maintenanceReasonLookupInputSchema>
export type DocumentTypeLookupInput = z.infer<typeof documentTypeLookupInputSchema>
export type ChecklistTemplateLookupInput = z.infer<typeof checklistTemplateLookupInputSchema>

export type MaintenanceCatalogQueryProjection = 'list' | 'get' | 'lookup' | 'preview'
export type MaintenanceCatalogResource = 'categories' | 'subcategories' | 'reasons' | 'document-types' | 'checklist-templates' | 'template-cw'

export function maintenanceCatalogQueryKey(
  tenantId: string,
  resource: MaintenanceCatalogResource,
  projection: MaintenanceCatalogQueryProjection,
  filters: Readonly<Record<string, string | number | null>> = {},
): readonly unknown[] {
  return ['tenant', tenantId, 'maintenance-catalogs', resource, projection, filters] as const
}
