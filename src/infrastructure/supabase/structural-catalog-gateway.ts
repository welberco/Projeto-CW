import type { ZodType } from 'zod'
import type { AppSupabaseClient } from '@/infrastructure/supabase/client'
import { AppError } from '@/shared/errors/app-error'
import {
  costCenterChildSchema,
  costCenterDetailSchema,
  costCenterListItemSchema,
  locationChildSchema,
  locationDetailSchema,
  locationListItemSchema,
  locationTypeDetailSchema,
  locationTypeListItemSchema,
  sectorDetailSchema,
  sectorListItemSchema,
  structuralCatalogLookupSchema,
  structuralCatalogResultSchema,
  type CatalogStatus,
  type CostCenterChild,
  type CostCenterDetail,
  type CostCenterListItem,
  type LocationChild,
  type LocationDetail,
  type LocationListItem,
  type LocationTypeDetail,
  type LocationTypeListItem,
  type SectorDetail,
  type SectorListItem,
  type StructuralCatalogLookup,
  type StructuralCatalogResult,
} from '@/shared/catalogs/structural-catalog'

interface CommandContext {
  readonly reason: string
  readonly correlationId: string
  readonly idempotencyKey: string
}

interface VersionedCommandInput extends CommandContext {
  readonly id: string
  readonly expectedVersion: number
}

export interface CatalogListInput {
  readonly searchText?: string | null
  readonly status?: CatalogStatus | null
  readonly limit?: number
  readonly offset?: number
}

export interface LocationTypeCreateInput extends CommandContext {
  readonly code: string
  readonly name: string
  readonly description: string | null
}

export interface LocationTypeUpdateInput extends VersionedCommandInput {
  readonly code: string
  readonly name: string
  readonly description: string | null
}

export interface LocationCreateInput extends CommandContext {
  readonly locationTypeId: string
  readonly parentId: string | null
  readonly code: string | null
  readonly name: string
  readonly description: string | null
}

export interface LocationUpdateInput extends VersionedCommandInput {
  readonly locationTypeId: string
  readonly code: string | null
  readonly name: string
  readonly description: string | null
}

export interface CostCenterCreateInput extends CommandContext {
  readonly parentId: string | null
  readonly code: string
  readonly name: string
  readonly description: string | null
}

export interface CostCenterUpdateInput extends VersionedCommandInput {
  readonly code: string
  readonly name: string
  readonly description: string | null
}

export interface SectorCreateInput extends CommandContext {
  readonly code: string | null
  readonly name: string
  readonly description: string | null
}

export interface SectorUpdateInput extends VersionedCommandInput {
  readonly code: string | null
  readonly name: string
  readonly description: string | null
}

export interface MoveCatalogInput extends VersionedCommandInput {
  readonly parentId: string | null
}

export type CatalogStatusCommandInput = VersionedCommandInput

export interface StructuralCatalogGateway {
  createLocationType(input: LocationTypeCreateInput): Promise<StructuralCatalogResult>
  updateLocationType(input: LocationTypeUpdateInput): Promise<StructuralCatalogResult>
  inactivateLocationType(input: CatalogStatusCommandInput): Promise<StructuralCatalogResult>
  reactivateLocationType(input: CatalogStatusCommandInput): Promise<StructuralCatalogResult>
  createLocation(input: LocationCreateInput): Promise<StructuralCatalogResult>
  updateLocation(input: LocationUpdateInput): Promise<StructuralCatalogResult>
  moveLocation(input: MoveCatalogInput): Promise<StructuralCatalogResult>
  inactivateLocation(input: CatalogStatusCommandInput): Promise<StructuralCatalogResult>
  reactivateLocation(input: CatalogStatusCommandInput): Promise<StructuralCatalogResult>
  createCostCenter(input: CostCenterCreateInput): Promise<StructuralCatalogResult>
  updateCostCenter(input: CostCenterUpdateInput): Promise<StructuralCatalogResult>
  moveCostCenter(input: MoveCatalogInput): Promise<StructuralCatalogResult>
  inactivateCostCenter(input: CatalogStatusCommandInput): Promise<StructuralCatalogResult>
  reactivateCostCenter(input: CatalogStatusCommandInput): Promise<StructuralCatalogResult>
  createSector(input: SectorCreateInput): Promise<StructuralCatalogResult>
  updateSector(input: SectorUpdateInput): Promise<StructuralCatalogResult>
  inactivateSector(input: CatalogStatusCommandInput): Promise<StructuralCatalogResult>
  reactivateSector(input: CatalogStatusCommandInput): Promise<StructuralCatalogResult>
  listLocationTypes(input?: CatalogListInput): Promise<readonly LocationTypeListItem[]>
  getLocationType(id: string): Promise<LocationTypeDetail | null>
  lookupLocationTypes(searchText?: string | null, limit?: number): Promise<readonly StructuralCatalogLookup[]>
  listLocations(input?: CatalogListInput): Promise<readonly LocationListItem[]>
  getLocation(id: string): Promise<LocationDetail | null>
  lookupLocations(searchText?: string | null, limit?: number): Promise<readonly StructuralCatalogLookup[]>
  listLocationChildren(parentId?: string | null): Promise<readonly LocationChild[]>
  listCostCenters(input?: CatalogListInput): Promise<readonly CostCenterListItem[]>
  getCostCenter(id: string): Promise<CostCenterDetail | null>
  lookupCostCenters(searchText?: string | null, limit?: number): Promise<readonly StructuralCatalogLookup[]>
  listCostCenterChildren(parentId?: string | null): Promise<readonly CostCenterChild[]>
  listSectors(input?: CatalogListInput): Promise<readonly SectorListItem[]>
  getSector(id: string): Promise<SectorDetail | null>
  lookupSectors(searchText?: string | null, limit?: number): Promise<readonly StructuralCatalogLookup[]>
}

type RpcRequest = PromiseLike<{ data: unknown; error: unknown }>

function unavailable(cause: unknown): AppError {
  return new AppError({
    code: 'STRUCTURAL_CATALOG_UNAVAILABLE',
    category: 'unavailable',
    userMessage: 'Não foi possível acessar o cadastro com segurança.',
    cause,
  })
}

async function parseRpc<T>(request: RpcRequest, schema: ZodType<T>): Promise<T> {
  const { data, error } = await request
  if (error !== null) throw unavailable(error)
  const parsed = schema.safeParse(data)
  if (!parsed.success) throw unavailable(parsed.error)
  return parsed.data
}

function command(request: RpcRequest): Promise<StructuralCatalogResult> {
  return parseRpc(request, structuralCatalogResultSchema)
}

function rows<T>(request: RpcRequest, schema: ZodType<T>): Promise<readonly T[]> {
  return parseRpc(request, schema.array())
}

async function detail<T>(request: RpcRequest, schema: ZodType<T>): Promise<T | null> {
  const result = await parseRpc(request, schema.array().max(1))
  return result[0] ?? null
}

// PostgreSQL accepts NULL for these arguments, while generated RPC metadata cannot
// express argument/RETURNS TABLE nullability. Keep that adaptation narrow and local.
function sqlNullable<T>(value: T | null): T {
  return value as T
}

function listArgs(input: CatalogListInput = {}) {
  return {
    search_text: sqlNullable(input.searchText ?? null),
    status_filter: sqlNullable(input.status ?? null),
    result_limit: input.limit ?? 50,
    result_offset: input.offset ?? 0,
  }
}

function contextArgs(input: CommandContext) {
  return {
    reason: input.reason,
    correlation_id: input.correlationId,
    idempotency_key: input.idempotencyKey,
  }
}

function versionedArgs(input: VersionedCommandInput) {
  return {
    id: input.id,
    expected_version: input.expectedVersion,
    ...contextArgs(input),
  }
}

export function createStructuralCatalogGateway(
  client: AppSupabaseClient,
): StructuralCatalogGateway {
  return {
    createLocationType(input) {
      return command(client.rpc('create_location_type', {
        code: input.code,
        name: input.name,
        description: sqlNullable(input.description),
        ...contextArgs(input),
      }))
    },
    updateLocationType(input) {
      return command(client.rpc('update_location_type', {
        ...versionedArgs(input),
        code: input.code,
        name: input.name,
        description: sqlNullable(input.description),
      }))
    },
    inactivateLocationType(input) {
      return command(client.rpc('inactivate_location_type', versionedArgs(input)))
    },
    reactivateLocationType(input) {
      return command(client.rpc('reactivate_location_type', versionedArgs(input)))
    },
    createLocation(input) {
      return command(client.rpc('create_location', {
        location_type_id: input.locationTypeId,
        parent_id: sqlNullable(input.parentId),
        code: sqlNullable(input.code),
        name: input.name,
        description: sqlNullable(input.description),
        ...contextArgs(input),
      }))
    },
    updateLocation(input) {
      return command(client.rpc('update_location', {
        ...versionedArgs(input),
        location_type_id: input.locationTypeId,
        code: sqlNullable(input.code),
        name: input.name,
        description: sqlNullable(input.description),
      }))
    },
    moveLocation(input) {
      return command(client.rpc('move_location', {
        ...versionedArgs(input),
        parent_id: sqlNullable(input.parentId),
      }))
    },
    inactivateLocation(input) {
      return command(client.rpc('inactivate_location', versionedArgs(input)))
    },
    reactivateLocation(input) {
      return command(client.rpc('reactivate_location', versionedArgs(input)))
    },
    createCostCenter(input) {
      return command(client.rpc('create_cost_center', {
        parent_id: sqlNullable(input.parentId),
        code: input.code,
        name: input.name,
        description: sqlNullable(input.description),
        ...contextArgs(input),
      }))
    },
    updateCostCenter(input) {
      return command(client.rpc('update_cost_center', {
        ...versionedArgs(input),
        code: input.code,
        name: input.name,
        description: sqlNullable(input.description),
      }))
    },
    moveCostCenter(input) {
      return command(client.rpc('move_cost_center', {
        ...versionedArgs(input),
        parent_id: sqlNullable(input.parentId),
      }))
    },
    inactivateCostCenter(input) {
      return command(client.rpc('inactivate_cost_center', versionedArgs(input)))
    },
    reactivateCostCenter(input) {
      return command(client.rpc('reactivate_cost_center', versionedArgs(input)))
    },
    createSector(input) {
      return command(client.rpc('create_sector', {
        code: sqlNullable(input.code),
        name: input.name,
        description: sqlNullable(input.description),
        ...contextArgs(input),
      }))
    },
    updateSector(input) {
      return command(client.rpc('update_sector', {
        ...versionedArgs(input),
        code: sqlNullable(input.code),
        name: input.name,
        description: sqlNullable(input.description),
      }))
    },
    inactivateSector(input) {
      return command(client.rpc('inactivate_sector', versionedArgs(input)))
    },
    reactivateSector(input) {
      return command(client.rpc('reactivate_sector', versionedArgs(input)))
    },
    listLocationTypes(input) {
      return rows(client.rpc('list_location_types', listArgs(input)), locationTypeListItemSchema)
    },
    getLocationType(id) {
      return detail(client.rpc('get_location_type', { target_id: id }), locationTypeDetailSchema)
    },
    lookupLocationTypes(searchText = null, limit = 20) {
      return rows(client.rpc('lookup_location_types', {
        search_text: sqlNullable(searchText), result_limit: limit,
      }), structuralCatalogLookupSchema)
    },
    listLocations(input) {
      return rows(client.rpc('list_locations', listArgs(input)), locationListItemSchema)
    },
    getLocation(id) {
      return detail(client.rpc('get_location', { target_id: id }), locationDetailSchema)
    },
    lookupLocations(searchText = null, limit = 20) {
      return rows(client.rpc('lookup_locations', {
        search_text: sqlNullable(searchText), result_limit: limit,
      }), structuralCatalogLookupSchema)
    },
    listLocationChildren(parentId = null) {
      return rows(client.rpc('list_location_children', {
        target_parent_id: sqlNullable(parentId),
      }), locationChildSchema)
    },
    listCostCenters(input) {
      return rows(client.rpc('list_cost_centers', listArgs(input)), costCenterListItemSchema)
    },
    getCostCenter(id) {
      return detail(client.rpc('get_cost_center', { target_id: id }), costCenterDetailSchema)
    },
    lookupCostCenters(searchText = null, limit = 20) {
      return rows(client.rpc('lookup_cost_centers', {
        search_text: sqlNullable(searchText), result_limit: limit,
      }), structuralCatalogLookupSchema)
    },
    listCostCenterChildren(parentId = null) {
      return rows(client.rpc('list_cost_center_children', {
        target_parent_id: sqlNullable(parentId),
      }), costCenterChildSchema)
    },
    listSectors(input) {
      return rows(client.rpc('list_sectors', listArgs(input)), sectorListItemSchema)
    },
    getSector(id) {
      return detail(client.rpc('get_sector', { target_id: id }), sectorDetailSchema)
    },
    lookupSectors(searchText = null, limit = 20) {
      return rows(client.rpc('lookup_sectors', {
        search_text: sqlNullable(searchText), result_limit: limit,
      }), structuralCatalogLookupSchema)
    },
  }
}
