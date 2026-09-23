import type { ZodType } from 'zod'
import type { AppSupabaseClient } from '@/infrastructure/supabase/client'
import { AppError, type AppErrorCategory } from '@/shared/errors/app-error'
import {
  applyCatalogTemplateInputSchema,
  catalogTemplateApplyResultSchema,
  catalogTemplatePreviewInputSchema,
  catalogTemplatePreviewSchema,
  checklistTemplateListInputSchema,
  checklistTemplateListItemSchema,
  checklistTemplateLookupInputSchema,
  checklistTemplateLookupSchema,
  checklistTemplateSchema,
  checklistTemplateStatusCommandInputSchema,
  createChecklistTemplateInputSchema,
  createDocumentTypeInputSchema,
  createMaintenanceCategoryInputSchema,
  createMaintenanceReasonInputSchema,
  createMaintenanceSubcategoryInputSchema,
  documentTypeListInputSchema,
  documentTypeListItemSchema,
  documentTypeLookupInputSchema,
  documentTypeLookupSchema,
  documentTypeSchema,
  documentTypeStatusCommandInputSchema,
  maintenanceCatalogCommandResultSchema,
  maintenanceCatalogIdSchema,
  maintenanceCategoryListInputSchema,
  maintenanceCategoryListItemSchema,
  maintenanceCategoryLookupInputSchema,
  maintenanceCategoryLookupSchema,
  maintenanceCategorySchema,
  maintenanceCategoryStatusCommandInputSchema,
  maintenanceReasonListInputSchema,
  maintenanceReasonListItemSchema,
  maintenanceReasonLookupInputSchema,
  maintenanceReasonLookupSchema,
  maintenanceReasonSchema,
  maintenanceReasonStatusCommandInputSchema,
  maintenanceSubcategoryListInputSchema,
  maintenanceSubcategoryListItemSchema,
  maintenanceSubcategoryLookupInputSchema,
  maintenanceSubcategoryLookupSchema,
  maintenanceSubcategorySchema,
  maintenanceSubcategoryStatusCommandInputSchema,
  updateChecklistTemplateDefinitionInputSchema,
  updateDocumentTypeInputSchema,
  updateMaintenanceCategoryInputSchema,
  updateMaintenanceReasonInputSchema,
  updateMaintenanceSubcategoryInputSchema,
  type ApplyCatalogTemplateInput,
  type CatalogTemplateApplyResult,
  type CatalogTemplatePreview,
  type ChecklistTemplate,
  type ChecklistTemplateListInput,
  type ChecklistTemplateListItem,
  type ChecklistTemplateLookup,
  type ChecklistTemplateLookupInput,
  type ChecklistTemplateStatusCommandInput,
  type CreateChecklistTemplateInput,
  type CreateDocumentTypeInput,
  type CreateMaintenanceCategoryInput,
  type CreateMaintenanceReasonInput,
  type CreateMaintenanceSubcategoryInput,
  type DocumentType,
  type DocumentTypeListInput,
  type DocumentTypeListItem,
  type DocumentTypeLookup,
  type DocumentTypeLookupInput,
  type DocumentTypeStatusCommandInput,
  type MaintenanceCatalogCommandResult,
  type MaintenanceCategory,
  type MaintenanceCategoryListInput,
  type MaintenanceCategoryListItem,
  type MaintenanceCategoryLookup,
  type MaintenanceCategoryLookupInput,
  type MaintenanceCategoryStatusCommandInput,
  type MaintenanceReason,
  type MaintenanceReasonListInput,
  type MaintenanceReasonListItem,
  type MaintenanceReasonLookup,
  type MaintenanceReasonLookupInput,
  type MaintenanceReasonStatusCommandInput,
  type MaintenanceSubcategory,
  type MaintenanceSubcategoryListInput,
  type MaintenanceSubcategoryListItem,
  type MaintenanceSubcategoryLookup,
  type MaintenanceSubcategoryLookupInput,
  type MaintenanceSubcategoryStatusCommandInput,
  type UpdateChecklistTemplateDefinitionInput,
  type UpdateDocumentTypeInput,
  type UpdateMaintenanceCategoryInput,
  type UpdateMaintenanceReasonInput,
  type UpdateMaintenanceSubcategoryInput,
} from '@/shared/maintenance-catalogs/maintenance-catalogs'

type RpcRequest = PromiseLike<{ data: unknown; error: unknown }>

interface RpcErrorShape { readonly code?: unknown; readonly message?: unknown }

export interface MaintenanceCatalogGateway {
  createMaintenanceCategory(input: CreateMaintenanceCategoryInput): Promise<MaintenanceCatalogCommandResult>
  updateMaintenanceCategory(input: UpdateMaintenanceCategoryInput): Promise<MaintenanceCatalogCommandResult>
  inactivateMaintenanceCategory(input: MaintenanceCategoryStatusCommandInput): Promise<MaintenanceCatalogCommandResult>
  reactivateMaintenanceCategory(input: MaintenanceCategoryStatusCommandInput): Promise<MaintenanceCatalogCommandResult>
  createMaintenanceSubcategory(input: CreateMaintenanceSubcategoryInput): Promise<MaintenanceCatalogCommandResult>
  updateMaintenanceSubcategory(input: UpdateMaintenanceSubcategoryInput): Promise<MaintenanceCatalogCommandResult>
  inactivateMaintenanceSubcategory(input: MaintenanceSubcategoryStatusCommandInput): Promise<MaintenanceCatalogCommandResult>
  reactivateMaintenanceSubcategory(input: MaintenanceSubcategoryStatusCommandInput): Promise<MaintenanceCatalogCommandResult>
  applyCatalogTemplate(input: ApplyCatalogTemplateInput): Promise<CatalogTemplateApplyResult>
  createMaintenanceReason(input: CreateMaintenanceReasonInput): Promise<MaintenanceCatalogCommandResult>
  updateMaintenanceReason(input: UpdateMaintenanceReasonInput): Promise<MaintenanceCatalogCommandResult>
  inactivateMaintenanceReason(input: MaintenanceReasonStatusCommandInput): Promise<MaintenanceCatalogCommandResult>
  reactivateMaintenanceReason(input: MaintenanceReasonStatusCommandInput): Promise<MaintenanceCatalogCommandResult>
  createDocumentType(input: CreateDocumentTypeInput): Promise<MaintenanceCatalogCommandResult>
  updateDocumentType(input: UpdateDocumentTypeInput): Promise<MaintenanceCatalogCommandResult>
  inactivateDocumentType(input: DocumentTypeStatusCommandInput): Promise<MaintenanceCatalogCommandResult>
  reactivateDocumentType(input: DocumentTypeStatusCommandInput): Promise<MaintenanceCatalogCommandResult>
  createChecklistTemplate(input: CreateChecklistTemplateInput): Promise<MaintenanceCatalogCommandResult>
  updateChecklistTemplateDefinition(input: UpdateChecklistTemplateDefinitionInput): Promise<MaintenanceCatalogCommandResult>
  inactivateChecklistTemplate(input: ChecklistTemplateStatusCommandInput): Promise<MaintenanceCatalogCommandResult>
  reactivateChecklistTemplate(input: ChecklistTemplateStatusCommandInput): Promise<MaintenanceCatalogCommandResult>
  listMaintenanceCategories(input?: MaintenanceCategoryListInput): Promise<readonly MaintenanceCategoryListItem[]>
  getMaintenanceCategory(id: string): Promise<MaintenanceCategory | null>
  lookupMaintenanceCategories(input?: MaintenanceCategoryLookupInput): Promise<readonly MaintenanceCategoryLookup[]>
  listMaintenanceSubcategories(input?: MaintenanceSubcategoryListInput): Promise<readonly MaintenanceSubcategoryListItem[]>
  getMaintenanceSubcategory(id: string): Promise<MaintenanceSubcategory | null>
  lookupMaintenanceSubcategories(input?: MaintenanceSubcategoryLookupInput): Promise<readonly MaintenanceSubcategoryLookup[]>
  getCatalogTemplatePreview(input?: { readonly templateKey?: 'cw_maintenance_taxonomy'; readonly templateVersion?: 1 }): Promise<CatalogTemplatePreview>
  listMaintenanceReasons(input?: MaintenanceReasonListInput): Promise<readonly MaintenanceReasonListItem[]>
  getMaintenanceReason(id: string): Promise<MaintenanceReason | null>
  lookupMaintenanceReasons(input: MaintenanceReasonLookupInput): Promise<readonly MaintenanceReasonLookup[]>
  listDocumentTypes(input?: DocumentTypeListInput): Promise<readonly DocumentTypeListItem[]>
  getDocumentType(id: string): Promise<DocumentType | null>
  lookupDocumentTypes(input?: DocumentTypeLookupInput): Promise<readonly DocumentTypeLookup[]>
  listChecklistTemplates(input?: ChecklistTemplateListInput): Promise<readonly ChecklistTemplateListItem[]>
  getChecklistTemplate(id: string): Promise<ChecklistTemplate | null>
  lookupChecklistTemplates(input?: ChecklistTemplateLookupInput): Promise<readonly ChecklistTemplateLookup[]>
}

function errorFromRpc(error: unknown): AppError {
  const source = error as RpcErrorShape | null
  const sqlState = typeof source?.code === 'string' ? source.code : undefined
  const message = typeof source?.message === 'string' ? source.message : undefined
  const code = message?.match(/\b[A-Z][A-Z0-9_]+\b/)?.[0] ?? 'MAINTENANCE_CATALOG_BOUNDARY_UNAVAILABLE'
  let category: AppErrorCategory = 'unavailable'
  if (sqlState === '42501' || code === 'AUTHORIZATION_DENIED') category = 'forbidden'
  else if (code.includes('VERSION_CONFLICT') || code.includes('IDEMPOTENCY_CONFLICT')) category = 'conflict'
  else if (code.includes('STATE') || code.includes('UNAVAILABLE')) category = 'invalid_state'
  else if (sqlState === '22023' || code.startsWith('INVALID_')) category = 'validation'
  return new AppError({ code, category, userMessage: 'Não foi possível acessar o catálogo de manutenção com segurança.', cause: error })
}

function invalidResponse(cause: unknown): AppError {
  return new AppError({
    code: 'MAINTENANCE_CATALOG_BOUNDARY_INVALID_RESPONSE',
    category: 'unavailable',
    userMessage: 'A resposta do catálogo de manutenção é inválida.',
    cause,
  })
}

async function parseRpc<T>(request: RpcRequest, schema: ZodType<T>): Promise<T> {
  const { data, error } = await request
  if (error !== null) throw errorFromRpc(error)
  const parsed = schema.safeParse(data)
  if (!parsed.success) throw invalidResponse(parsed.error)
  return parsed.data
}
function command(request: RpcRequest): Promise<MaintenanceCatalogCommandResult> { return parseRpc(request, maintenanceCatalogCommandResultSchema) }
function rows<T>(request: RpcRequest, schema: ZodType<T>): Promise<readonly T[]> { return parseRpc(request, schema.array()) }
async function detail<T>(request: RpcRequest, schema: ZodType<T>): Promise<T | null> { const result = await rows(request, schema); if (result.length > 1) throw invalidResponse('detail returned multiple rows'); return result[0] ?? null }
function sqlNullable<T>(value: T | null): T { return value as T }
function contextArgs(input: { readonly reason: string; readonly correlationId: string; readonly idempotencyKey: string }) { return { reason: input.reason, correlation_id: input.correlationId, idempotency_key: input.idempotencyKey } }
function versionedArgs(input: { readonly id: string; readonly expectedVersion: number; readonly reason: string; readonly correlationId: string; readonly idempotencyKey: string }) { return { id: input.id, expected_version: input.expectedVersion, ...contextArgs(input) } }
function listArgs(input: { readonly searchText?: string | null | undefined; readonly status?: 'active' | 'inactive' | null | undefined; readonly limit?: number | undefined; readonly offset?: number | undefined } = {}) { return { search_text: sqlNullable(input.searchText ?? null), status_filter: sqlNullable(input.status ?? null), result_limit: input.limit ?? 50, result_offset: input.offset ?? 0 } }

export function createMaintenanceCatalogGateway(client: AppSupabaseClient): MaintenanceCatalogGateway {
  return {
    createMaintenanceCategory(raw) { const input = createMaintenanceCategoryInputSchema.parse(raw); return command(client.rpc('create_maintenance_category', { code: sqlNullable(input.code), name: input.name, description: sqlNullable(input.description), ...contextArgs(input) })) },
    updateMaintenanceCategory(raw) { const input = updateMaintenanceCategoryInputSchema.parse(raw); return command(client.rpc('update_maintenance_category', { ...versionedArgs(input), code: sqlNullable(input.code), name: input.name, description: sqlNullable(input.description) })) },
    inactivateMaintenanceCategory(raw) { const input = maintenanceCategoryStatusCommandInputSchema.parse(raw); return command(client.rpc('inactivate_maintenance_category', versionedArgs(input))) },
    reactivateMaintenanceCategory(raw) { const input = maintenanceCategoryStatusCommandInputSchema.parse(raw); return command(client.rpc('reactivate_maintenance_category', versionedArgs(input))) },
    createMaintenanceSubcategory(raw) { const input = createMaintenanceSubcategoryInputSchema.parse(raw); return command(client.rpc('create_maintenance_subcategory', { category_id: input.categoryId, code: sqlNullable(input.code), name: input.name, description: sqlNullable(input.description), ...contextArgs(input) })) },
    updateMaintenanceSubcategory(raw) { const input = updateMaintenanceSubcategoryInputSchema.parse(raw); return command(client.rpc('update_maintenance_subcategory', { ...versionedArgs(input), category_id: input.categoryId, code: sqlNullable(input.code), name: input.name, description: sqlNullable(input.description) })) },
    inactivateMaintenanceSubcategory(raw) { const input = maintenanceSubcategoryStatusCommandInputSchema.parse(raw); return command(client.rpc('inactivate_maintenance_subcategory', versionedArgs(input))) },
    reactivateMaintenanceSubcategory(raw) { const input = maintenanceSubcategoryStatusCommandInputSchema.parse(raw); return command(client.rpc('reactivate_maintenance_subcategory', versionedArgs(input))) },
    applyCatalogTemplate(raw) { const input = applyCatalogTemplateInputSchema.parse(raw); return parseRpc(client.rpc('apply_cw_catalog_template', { template_key: input.templateKey, template_version: input.templateVersion, ...contextArgs(input) }), catalogTemplateApplyResultSchema) },
    createMaintenanceReason(raw) { const input = createMaintenanceReasonInputSchema.parse(raw); return command(client.rpc('create_maintenance_reason', { usage_context: input.usageContext, code: input.code, name: input.name, description: sqlNullable(input.description), ...contextArgs(input) })) },
    updateMaintenanceReason(raw) { const input = updateMaintenanceReasonInputSchema.parse(raw); return command(client.rpc('update_maintenance_reason', { ...versionedArgs(input), code: input.code, name: input.name, description: sqlNullable(input.description) })) },
    inactivateMaintenanceReason(raw) { const input = maintenanceReasonStatusCommandInputSchema.parse(raw); return command(client.rpc('inactivate_maintenance_reason', versionedArgs(input))) },
    reactivateMaintenanceReason(raw) { const input = maintenanceReasonStatusCommandInputSchema.parse(raw); return command(client.rpc('reactivate_maintenance_reason', versionedArgs(input))) },
    createDocumentType(raw) { const input = createDocumentTypeInputSchema.parse(raw); return command(client.rpc('create_document_type', { code: sqlNullable(input.code), name: input.name, description: sqlNullable(input.description), ...contextArgs(input) })) },
    updateDocumentType(raw) { const input = updateDocumentTypeInputSchema.parse(raw); return command(client.rpc('update_document_type', { ...versionedArgs(input), code: sqlNullable(input.code), name: input.name, description: sqlNullable(input.description) })) },
    inactivateDocumentType(raw) { const input = documentTypeStatusCommandInputSchema.parse(raw); return command(client.rpc('inactivate_document_type', versionedArgs(input))) },
    reactivateDocumentType(raw) { const input = documentTypeStatusCommandInputSchema.parse(raw); return command(client.rpc('reactivate_document_type', versionedArgs(input))) },
    createChecklistTemplate(raw) { const input = createChecklistTemplateInputSchema.parse(raw); return command(client.rpc('create_checklist_template', { category_id: input.categoryId, code: sqlNullable(input.code), name: input.name, description: sqlNullable(input.description), items: input.items, ...contextArgs(input) })) },
    updateChecklistTemplateDefinition(raw) { const input = updateChecklistTemplateDefinitionInputSchema.parse(raw); return command(client.rpc('update_checklist_template_definition', { ...versionedArgs(input), category_id: input.categoryId, code: sqlNullable(input.code), name: input.name, description: sqlNullable(input.description), items: input.items })) },
    inactivateChecklistTemplate(raw) { const input = checklistTemplateStatusCommandInputSchema.parse(raw); return command(client.rpc('inactivate_checklist_template', versionedArgs(input))) },
    reactivateChecklistTemplate(raw) { const input = checklistTemplateStatusCommandInputSchema.parse(raw); return command(client.rpc('reactivate_checklist_template', versionedArgs(input))) },
    listMaintenanceCategories(raw = {}) { const input = maintenanceCategoryListInputSchema.parse(raw); return rows(client.rpc('list_maintenance_categories', listArgs(input)), maintenanceCategoryListItemSchema) },
    getMaintenanceCategory(raw) { const id = maintenanceCatalogIdSchema.parse(raw); return detail(client.rpc('get_maintenance_category', { target_id: id }), maintenanceCategorySchema) },
    lookupMaintenanceCategories(raw = {}) { const input = maintenanceCategoryLookupInputSchema.parse(raw); return rows(client.rpc('lookup_maintenance_categories', { search_text: sqlNullable(input.searchText ?? null), result_limit: input.limit ?? 20 }), maintenanceCategoryLookupSchema) },
    listMaintenanceSubcategories(raw = {}) { const input = maintenanceSubcategoryListInputSchema.parse(raw); return rows(client.rpc('list_maintenance_subcategories', { ...listArgs(input), category_filter: sqlNullable(input.categoryId ?? null) }), maintenanceSubcategoryListItemSchema) },
    getMaintenanceSubcategory(raw) { const id = maintenanceCatalogIdSchema.parse(raw); return detail(client.rpc('get_maintenance_subcategory', { target_id: id }), maintenanceSubcategorySchema) },
    lookupMaintenanceSubcategories(raw = {}) { const input = maintenanceSubcategoryLookupInputSchema.parse(raw); return rows(client.rpc('lookup_maintenance_subcategories', { category_filter: sqlNullable(input.categoryId ?? null), search_text: sqlNullable(input.searchText ?? null), result_limit: input.limit ?? 20 }), maintenanceSubcategoryLookupSchema) },
    getCatalogTemplatePreview(raw = {}) { const input = catalogTemplatePreviewInputSchema.parse(raw); return parseRpc(client.rpc('get_cw_catalog_template_preview', { template_key: input.templateKey ?? 'cw_maintenance_taxonomy', template_version: input.templateVersion ?? 1 }), catalogTemplatePreviewSchema) },
    listMaintenanceReasons(raw = {}) { const input = maintenanceReasonListInputSchema.parse(raw); return rows(client.rpc('list_maintenance_reasons', { ...listArgs(input), usage_context_filter: sqlNullable(input.usageContext ?? null) }), maintenanceReasonListItemSchema) },
    getMaintenanceReason(raw) { const id = maintenanceCatalogIdSchema.parse(raw); return detail(client.rpc('get_maintenance_reason', { target_id: id }), maintenanceReasonSchema) },
    lookupMaintenanceReasons(raw) { const input = maintenanceReasonLookupInputSchema.parse(raw); return rows(client.rpc('lookup_maintenance_reasons', { usage_context: input.usageContext, search_text: sqlNullable(input.searchText ?? null), result_limit: input.limit ?? 20 }), maintenanceReasonLookupSchema) },
    listDocumentTypes(raw = {}) { const input = documentTypeListInputSchema.parse(raw); return rows(client.rpc('list_document_types', listArgs(input)), documentTypeListItemSchema) },
    getDocumentType(raw) { const id = maintenanceCatalogIdSchema.parse(raw); return detail(client.rpc('get_document_type', { target_id: id }), documentTypeSchema) },
    lookupDocumentTypes(raw = {}) { const input = documentTypeLookupInputSchema.parse(raw); return rows(client.rpc('lookup_document_types', { search_text: sqlNullable(input.searchText ?? null), result_limit: input.limit ?? 20 }), documentTypeLookupSchema) },
    listChecklistTemplates(raw = {}) { const input = checklistTemplateListInputSchema.parse(raw); return rows(client.rpc('list_checklist_templates', { ...listArgs(input), category_filter: sqlNullable(input.categoryId ?? null) }), checklistTemplateListItemSchema) },
    getChecklistTemplate(raw) { const id = maintenanceCatalogIdSchema.parse(raw); return detail(client.rpc('get_checklist_template', { target_id: id }), checklistTemplateSchema) },
    lookupChecklistTemplates(raw = {}) { const input = checklistTemplateLookupInputSchema.parse(raw); return rows(client.rpc('lookup_checklist_templates', { category_filter: sqlNullable(input.categoryId ?? null), search_text: sqlNullable(input.searchText ?? null), result_limit: input.limit ?? 20 }), checklistTemplateLookupSchema) },
  }
}
