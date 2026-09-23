import { describe, expect, it } from 'vitest'
import {
  applyCatalogTemplateInputSchema,
  catalogTemplateApplyResultSchema,
  catalogTemplatePreviewSchema,
  checklistTemplateItemInputSchema,
  checklistTemplateSchema,
  createChecklistTemplateInputSchema,
  createDocumentTypeInputSchema,
  createMaintenanceCategoryInputSchema,
  createMaintenanceReasonInputSchema,
  createMaintenanceSubcategoryInputSchema,
  documentTypeListItemSchema,
  documentTypeLookupSchema,
  maintenanceCatalogCommandResultSchema,
  maintenanceCatalogQueryKey,
  maintenanceCategoryListItemSchema,
  maintenanceCategoryLookupSchema,
  maintenanceReasonListItemSchema,
  maintenanceReasonLookupSchema,
  maintenanceSubcategoryListItemSchema,
  maintenanceSubcategoryLookupSchema,
  updateChecklistTemplateDefinitionInputSchema,
  updateDocumentTypeInputSchema,
  updateMaintenanceCategoryInputSchema,
  updateMaintenanceReasonInputSchema,
  updateMaintenanceSubcategoryInputSchema,
} from '@/shared/maintenance-catalogs/maintenance-catalogs'

const id = '11111111-1111-4111-8111-111111111111'
const relatedId = '22222222-2222-4222-8222-222222222222'
const correlationId = '33333333-3333-4333-8333-333333333333'
const timestamp = '2026-09-23T12:00:00.000Z'
const context = { reason: 'manutenção planejada', correlationId, idempotencyKey: 'w4c-command-0001' }
const definition = { code: 'ELETRICA', name: 'Elétrica', description: null }
const versioned = { id, expectedVersion: 1, ...context }
const checklistItems = [{ position: 1, prompt: 'Verificar quadro', response_type: 'YES_NO' as const, required: true, instructions: null }]
const listItem = { id, ...definition, status: 'active' as const, version: 1, updated_at: timestamp }

describe('W4C maintenance catalog boundary', () => {
  it('validates all 21 command inputs and does not accept client authority', () => {
    const cases = [
      [createMaintenanceCategoryInputSchema, { ...definition, ...context }],
      [updateMaintenanceCategoryInputSchema, { ...definition, ...versioned }],
      [createMaintenanceSubcategoryInputSchema, { ...definition, categoryId: relatedId, ...context }],
      [updateMaintenanceSubcategoryInputSchema, { ...definition, categoryId: relatedId, ...versioned }],
      [applyCatalogTemplateInputSchema, { templateKey: 'cw_maintenance_taxonomy', templateVersion: 1, ...context }],
      [createMaintenanceReasonInputSchema, { ...definition, usageContext: 'CANCEL_REQUEST', ...context }],
      [updateMaintenanceReasonInputSchema, { ...definition, ...versioned }],
      [createDocumentTypeInputSchema, { ...definition, ...context }],
      [updateDocumentTypeInputSchema, { ...definition, ...versioned }],
      [createChecklistTemplateInputSchema, { ...definition, categoryId: relatedId, items: checklistItems, ...context }],
      [updateChecklistTemplateDefinitionInputSchema, { ...definition, categoryId: relatedId, items: checklistItems, ...versioned }],
    ] as const

    for (const [schema, input] of cases) expect(schema.parse(input)).toEqual(input)
    expect(() => createMaintenanceCategoryInputSchema.parse({ ...definition, tenantId: id, ...context })).toThrow()
    expect(() => createMaintenanceReasonInputSchema.parse({ ...definition, code: null, usageContext: 'CANCEL_REQUEST', ...context })).toThrow()
  })

  it('enforces strict command results and the exact immutable template result', () => {
    const result = { id, version: 2, status: 'active', command_correlation_id: correlationId }
    expect(maintenanceCatalogCommandResultSchema.parse(result)).toEqual(result)
    expect(() => maintenanceCatalogCommandResultSchema.parse({ ...result, correlation_id: correlationId })).toThrow()
    expect(catalogTemplateApplyResultSchema.parse({
      id,
      version: 1,
      status: 'applied',
      command_correlation_id: correlationId,
      template_key: 'cw_maintenance_taxonomy',
      template_version: 1,
      category_ids: Array.from({ length: 11 }, () => id),
      subcategory_ids: Array.from({ length: 39 }, () => relatedId),
      category_count: 11,
      subcategory_count: 39,
    })).toMatchObject({ status: 'applied', category_count: 11, subcategory_count: 39 })
  })

  it('validates the sixteen exact projections and keeps lookup rows minimal', () => {
    expect(maintenanceCategoryListItemSchema.parse(listItem)).toEqual(listItem)
    expect(maintenanceSubcategoryListItemSchema.parse({ ...listItem, category_id: relatedId })).toMatchObject({ category_id: relatedId })
    expect(maintenanceReasonListItemSchema.parse({ ...listItem, usage_context: 'RETURN_WORK_ORDER' })).toMatchObject({ usage_context: 'RETURN_WORK_ORDER' })
    expect(documentTypeListItemSchema.parse(listItem)).toEqual(listItem)
    const lookup = { id, code: 'ELETRICA', name: 'Elétrica' }
    for (const schema of [maintenanceCategoryLookupSchema, maintenanceSubcategoryLookupSchema, maintenanceReasonLookupSchema, documentTypeLookupSchema]) {
      expect(schema.parse(lookup)).toEqual(lookup)
      expect(() => schema.parse({ ...lookup, status: 'active' })).toThrow()
    }
    expect(checklistTemplateSchema.parse({ ...listItem, category_id: relatedId, items: [{ id: relatedId, ...checklistItems[0] }], created_at: timestamp }))
    expect(() => checklistTemplateItemInputSchema.parse({ ...checklistItems[0], id })).toThrow()
  })

  it('rejects malformed version, enum, checklist and preview payloads', () => {
    expect(createChecklistTemplateInputSchema.parse({
      ...definition,
      categoryId: relatedId,
      items: [...checklistItems, { ...checklistItems[0], position: 2, prompt: 'Registrar leitura' }],
      ...context,
    }).items).toHaveLength(2)
    expect(() => updateMaintenanceCategoryInputSchema.parse({ ...definition, ...versioned, expectedVersion: 0 })).toThrow()
    expect(() => createMaintenanceReasonInputSchema.parse({ ...definition, usageContext: 'INVENTED', ...context })).toThrow()
    expect(() => createChecklistTemplateInputSchema.parse({ ...definition, categoryId: relatedId, items: [...checklistItems, { ...checklistItems[0] }], ...context })).toThrow()
    expect(() => checklistTemplateSchema.parse({
      ...listItem,
      category_id: relatedId,
      items: [{ id: relatedId, position: 2, prompt: 'Segundo', response_type: 'YES_NO', required: true, instructions: null }, { id, ...checklistItems[0] }],
      created_at: timestamp,
    })).toThrow()
    expect(() => catalogTemplatePreviewSchema.parse({
      template_key: 'cw_maintenance_taxonomy', template_version: 1, category_count: 11, subcategory_count: 39, categories: [],
    })).toThrow()
  })

  it('partitions cache keys by tenant, projection and filters', () => {
    expect(maintenanceCatalogQueryKey('tenant-a', 'categories', 'lookup', { search: 'eletrica' })).not.toEqual(
      maintenanceCatalogQueryKey('tenant-b', 'categories', 'lookup', { search: 'eletrica' }),
    )
    expect(maintenanceCatalogQueryKey('tenant-a', 'categories', 'lookup')).not.toEqual(
      maintenanceCatalogQueryKey('tenant-a', 'categories', 'list'),
    )
  })
})
