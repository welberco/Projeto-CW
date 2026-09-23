import { describe, expect, it, vi } from 'vitest'
import type { AppSupabaseClient } from '@/infrastructure/supabase/client'
import { createMaintenanceCatalogGateway, type MaintenanceCatalogGateway } from '@/infrastructure/supabase/maintenance-catalog-gateway'

const id = '11111111-1111-4111-8111-111111111111'
const relatedId = '22222222-2222-4222-8222-222222222222'
const correlationId = '33333333-3333-4333-8333-333333333333'
const timestamp = '2026-09-23T12:00:00.000Z'
const context = { reason: 'manutenção planejada', correlationId, idempotencyKey: 'w4c-command-0001' }
const rpcContext = { reason: context.reason, correlation_id: correlationId, idempotency_key: context.idempotencyKey }
const versioned = { id, expectedVersion: 1, ...context }
const versionedArgs = { id, expected_version: 1, ...rpcContext }
const definition = { code: 'ELETRICA', name: 'Elétrica', description: null }
const result = { id, version: 2, status: 'active', command_correlation_id: correlationId }
const item = { position: 1, prompt: 'Verificar quadro', response_type: 'YES_NO' as const, required: true, instructions: null }
const listRow = { id, ...definition, status: 'active', version: 1, updated_at: timestamp }
const lookupRow = { id, code: 'ELETRICA', name: 'Elétrica' }

function setup(data: unknown, error: unknown = null) {
  const rpc = vi.fn().mockResolvedValue({ data, error })
  const from = vi.fn()
  return { gateway: createMaintenanceCatalogGateway({ rpc, from } as unknown as AppSupabaseClient), rpc, from }
}

interface Case { readonly name: keyof MaintenanceCatalogGateway; readonly rpc: string; readonly args: Readonly<Record<string, unknown>>; readonly response: unknown; readonly invoke: (gateway: MaintenanceCatalogGateway) => Promise<unknown> }

const commandCases: readonly Case[] = [
  { name: 'createMaintenanceCategory', rpc: 'create_maintenance_category', args: { code: 'ELETRICA', name: 'Elétrica', description: null, ...rpcContext }, response: result, invoke: gateway => gateway.createMaintenanceCategory({ ...definition, ...context }) },
  { name: 'updateMaintenanceCategory', rpc: 'update_maintenance_category', args: { ...versionedArgs, ...definition }, response: result, invoke: gateway => gateway.updateMaintenanceCategory({ ...definition, ...versioned }) },
  { name: 'inactivateMaintenanceCategory', rpc: 'inactivate_maintenance_category', args: versionedArgs, response: { ...result, status: 'inactive' }, invoke: gateway => gateway.inactivateMaintenanceCategory(versioned) },
  { name: 'reactivateMaintenanceCategory', rpc: 'reactivate_maintenance_category', args: versionedArgs, response: result, invoke: gateway => gateway.reactivateMaintenanceCategory(versioned) },
  { name: 'createMaintenanceSubcategory', rpc: 'create_maintenance_subcategory', args: { category_id: relatedId, ...definition, ...rpcContext }, response: result, invoke: gateway => gateway.createMaintenanceSubcategory({ ...definition, categoryId: relatedId, ...context }) },
  { name: 'updateMaintenanceSubcategory', rpc: 'update_maintenance_subcategory', args: { ...versionedArgs, category_id: relatedId, ...definition }, response: result, invoke: gateway => gateway.updateMaintenanceSubcategory({ ...definition, categoryId: relatedId, ...versioned }) },
  { name: 'inactivateMaintenanceSubcategory', rpc: 'inactivate_maintenance_subcategory', args: versionedArgs, response: { ...result, status: 'inactive' }, invoke: gateway => gateway.inactivateMaintenanceSubcategory(versioned) },
  { name: 'reactivateMaintenanceSubcategory', rpc: 'reactivate_maintenance_subcategory', args: versionedArgs, response: result, invoke: gateway => gateway.reactivateMaintenanceSubcategory(versioned) },
  { name: 'applyCatalogTemplate', rpc: 'apply_cw_catalog_template', args: { template_key: 'cw_maintenance_taxonomy', template_version: 1, ...rpcContext }, response: { id, version: 1, status: 'applied', command_correlation_id: correlationId, template_key: 'cw_maintenance_taxonomy', template_version: 1, category_ids: Array.from({ length: 11 }, () => id), subcategory_ids: Array.from({ length: 39 }, () => relatedId), category_count: 11, subcategory_count: 39 }, invoke: gateway => gateway.applyCatalogTemplate({ templateKey: 'cw_maintenance_taxonomy', templateVersion: 1, ...context }) },
  { name: 'createMaintenanceReason', rpc: 'create_maintenance_reason', args: { usage_context: 'CANCEL_REQUEST', ...definition, ...rpcContext }, response: result, invoke: gateway => gateway.createMaintenanceReason({ ...definition, usageContext: 'CANCEL_REQUEST', ...context }) },
  { name: 'updateMaintenanceReason', rpc: 'update_maintenance_reason', args: { ...versionedArgs, ...definition }, response: result, invoke: gateway => gateway.updateMaintenanceReason({ ...definition, ...versioned }) },
  { name: 'inactivateMaintenanceReason', rpc: 'inactivate_maintenance_reason', args: versionedArgs, response: { ...result, status: 'inactive' }, invoke: gateway => gateway.inactivateMaintenanceReason(versioned) },
  { name: 'reactivateMaintenanceReason', rpc: 'reactivate_maintenance_reason', args: versionedArgs, response: result, invoke: gateway => gateway.reactivateMaintenanceReason(versioned) },
  { name: 'createDocumentType', rpc: 'create_document_type', args: { ...definition, ...rpcContext }, response: result, invoke: gateway => gateway.createDocumentType({ ...definition, ...context }) },
  { name: 'updateDocumentType', rpc: 'update_document_type', args: { ...versionedArgs, ...definition }, response: result, invoke: gateway => gateway.updateDocumentType({ ...definition, ...versioned }) },
  { name: 'inactivateDocumentType', rpc: 'inactivate_document_type', args: versionedArgs, response: { ...result, status: 'inactive' }, invoke: gateway => gateway.inactivateDocumentType(versioned) },
  { name: 'reactivateDocumentType', rpc: 'reactivate_document_type', args: versionedArgs, response: result, invoke: gateway => gateway.reactivateDocumentType(versioned) },
  { name: 'createChecklistTemplate', rpc: 'create_checklist_template', args: { category_id: relatedId, ...definition, items: [item], ...rpcContext }, response: result, invoke: gateway => gateway.createChecklistTemplate({ ...definition, categoryId: relatedId, items: [item], ...context }) },
  { name: 'updateChecklistTemplateDefinition', rpc: 'update_checklist_template_definition', args: { ...versionedArgs, category_id: relatedId, ...definition, items: [item] }, response: result, invoke: gateway => gateway.updateChecklistTemplateDefinition({ ...definition, categoryId: relatedId, items: [item], ...versioned }) },
  { name: 'inactivateChecklistTemplate', rpc: 'inactivate_checklist_template', args: versionedArgs, response: { ...result, status: 'inactive' }, invoke: gateway => gateway.inactivateChecklistTemplate(versioned) },
  { name: 'reactivateChecklistTemplate', rpc: 'reactivate_checklist_template', args: versionedArgs, response: result, invoke: gateway => gateway.reactivateChecklistTemplate(versioned) },
]

const readCases: readonly Case[] = [
  { name: 'listMaintenanceCategories', rpc: 'list_maintenance_categories', args: { search_text: 'ele', status_filter: 'active', result_limit: 10, result_offset: 2 }, response: [listRow], invoke: gateway => gateway.listMaintenanceCategories({ searchText: 'ele', status: 'active', limit: 10, offset: 2 }) },
  { name: 'getMaintenanceCategory', rpc: 'get_maintenance_category', args: { target_id: id }, response: [{ ...listRow, created_at: timestamp }], invoke: gateway => gateway.getMaintenanceCategory(id) },
  { name: 'lookupMaintenanceCategories', rpc: 'lookup_maintenance_categories', args: { search_text: null, result_limit: 20 }, response: [lookupRow], invoke: gateway => gateway.lookupMaintenanceCategories() },
  { name: 'listMaintenanceSubcategories', rpc: 'list_maintenance_subcategories', args: { category_filter: relatedId, search_text: null, status_filter: null, result_limit: 50, result_offset: 0 }, response: [{ ...listRow, category_id: relatedId }], invoke: gateway => gateway.listMaintenanceSubcategories({ categoryId: relatedId }) },
  { name: 'getMaintenanceSubcategory', rpc: 'get_maintenance_subcategory', args: { target_id: id }, response: [{ ...listRow, category_id: relatedId, created_at: timestamp }], invoke: gateway => gateway.getMaintenanceSubcategory(id) },
  { name: 'lookupMaintenanceSubcategories', rpc: 'lookup_maintenance_subcategories', args: { category_filter: null, search_text: null, result_limit: 20 }, response: [lookupRow], invoke: gateway => gateway.lookupMaintenanceSubcategories() },
  { name: 'getCatalogTemplatePreview', rpc: 'get_cw_catalog_template_preview', args: { template_key: 'cw_maintenance_taxonomy', template_version: 1 }, response: { template_key: 'cw_maintenance_taxonomy', template_version: 1, category_count: 11, subcategory_count: 39, categories: Array.from({ length: 11 }, (_, index) => ({ key: `category-${index}`, code: `C${index}`, name: `Categoria ${index}`, subcategories: [] })) }, invoke: gateway => gateway.getCatalogTemplatePreview() },
  { name: 'listMaintenanceReasons', rpc: 'list_maintenance_reasons', args: { usage_context_filter: 'CANCEL_REQUEST', search_text: null, status_filter: null, result_limit: 50, result_offset: 0 }, response: [{ ...listRow, usage_context: 'CANCEL_REQUEST' }], invoke: gateway => gateway.listMaintenanceReasons({ usageContext: 'CANCEL_REQUEST' }) },
  { name: 'getMaintenanceReason', rpc: 'get_maintenance_reason', args: { target_id: id }, response: [{ ...listRow, usage_context: 'CANCEL_REQUEST', created_at: timestamp }], invoke: gateway => gateway.getMaintenanceReason(id) },
  { name: 'lookupMaintenanceReasons', rpc: 'lookup_maintenance_reasons', args: { usage_context: 'CANCEL_REQUEST', search_text: null, result_limit: 20 }, response: [lookupRow], invoke: gateway => gateway.lookupMaintenanceReasons({ usageContext: 'CANCEL_REQUEST' }) },
  { name: 'listDocumentTypes', rpc: 'list_document_types', args: { search_text: null, status_filter: null, result_limit: 50, result_offset: 0 }, response: [listRow], invoke: gateway => gateway.listDocumentTypes() },
  { name: 'getDocumentType', rpc: 'get_document_type', args: { target_id: id }, response: [{ ...listRow, created_at: timestamp }], invoke: gateway => gateway.getDocumentType(id) },
  { name: 'lookupDocumentTypes', rpc: 'lookup_document_types', args: { search_text: null, result_limit: 20 }, response: [lookupRow], invoke: gateway => gateway.lookupDocumentTypes() },
  { name: 'listChecklistTemplates', rpc: 'list_checklist_templates', args: { category_filter: relatedId, search_text: null, status_filter: null, result_limit: 50, result_offset: 0 }, response: [{ ...listRow, category_id: relatedId, item_count: 1 }], invoke: gateway => gateway.listChecklistTemplates({ categoryId: relatedId }) },
  { name: 'getChecklistTemplate', rpc: 'get_checklist_template', args: { target_id: id }, response: [{ ...listRow, category_id: relatedId, items: [{ id: relatedId, ...item }], created_at: timestamp }], invoke: gateway => gateway.getChecklistTemplate(id) },
  { name: 'lookupChecklistTemplates', rpc: 'lookup_checklist_templates', args: { category_filter: null, search_text: null, result_limit: 20 }, response: [{ ...lookupRow, category_id: relatedId }], invoke: gateway => gateway.lookupChecklistTemplates() },
]

describe('W4C maintenance catalog gateway', () => {
  it('exposes exactly the approved 21 commands and 16 reads', () => {
    expect(commandCases).toHaveLength(21)
    expect(readCases).toHaveLength(16)
    const { gateway } = setup([])
    expect(Object.keys(gateway)).toEqual([
      ...commandCases.map(({ name }) => name),
      ...readCases.map(({ name }) => name),
    ])
  })

  it.each(commandCases)('$name maps every approved command only through its RPC', async ({ rpc: rpcName, args, response, invoke }) => {
    const { gateway, rpc, from } = setup(response)
    await expect(invoke(gateway)).resolves.toEqual(response)
    expect(rpc).toHaveBeenCalledWith(rpcName, args)
    expect(from).not.toHaveBeenCalled()
  })

  it.each(readCases)('$name maps every approved read only through its RPC', async ({ rpc: rpcName, args, response, invoke }) => {
    const { gateway, rpc, from } = setup(response)
    await expect(invoke(gateway)).resolves.toEqual(Array.isArray(response) && rpcName.startsWith('get_') ? response[0] : response)
    expect(rpc).toHaveBeenCalledWith(rpcName, args)
    expect(from).not.toHaveBeenCalled()
  })

  it('rejects malformed output and preserves authorization and concurrency errors', async () => {
    const malformed = setup([{ ...lookupRow, status: 'active' }])
    await expect(malformed.gateway.lookupDocumentTypes()).rejects.toMatchObject({ code: 'MAINTENANCE_CATALOG_BOUNDARY_INVALID_RESPONSE' })
    const forbidden = setup(null, { code: '42501', message: 'AUTHORIZATION_DENIED' })
    await expect(forbidden.gateway.listMaintenanceCategories()).rejects.toMatchObject({ category: 'forbidden' })
    const conflict = setup(null, { code: 'P0001', message: 'MAINTENANCE_CATEGORY_VERSION_CONFLICT' })
    await expect(conflict.gateway.inactivateMaintenanceCategory(versioned)).rejects.toMatchObject({ category: 'conflict' })
  })

  it('rejects invalid format and client authority before calling the RPC', () => {
    const { gateway, rpc } = setup(result)
    expect(() => gateway.getMaintenanceCategory('not-a-uuid')).toThrow()
    expect(() => gateway.createMaintenanceCategory({ ...definition, tenantId: id, ...context } as never)).toThrow()
    expect(rpc).not.toHaveBeenCalled()
  })
})
