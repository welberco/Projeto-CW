import { describe, expect, it, vi } from 'vitest'
import type { AppSupabaseClient } from '@/infrastructure/supabase/client'
import {
  createStructuralCatalogGateway,
  type StructuralCatalogGateway,
} from '@/infrastructure/supabase/structural-catalog-gateway'

const id = '11111111-1111-4111-8111-111111111111'
const relationId = '33333333-3333-4333-8333-333333333333'
const correlationId = '22222222-2222-4222-8222-222222222222'
const timestamp = '2026-09-17T12:00:00.000Z'
const context = {
  reason: 'alteração estrutural',
  correlationId,
  idempotencyKey: 'w4a-command-0001',
}
const rpcContext = {
  reason: context.reason,
  correlation_id: correlationId,
  idempotency_key: context.idempotencyKey,
}
const commandResult = {
  id,
  version: 2,
  status: 'active',
  command_correlation_id: correlationId,
}
const versionedInput = { id, expectedVersion: 1, ...context }
const versionedArgs = { id, expected_version: 1, ...rpcContext }

function setup(data: unknown, error: unknown = null) {
  const rpc = vi.fn().mockResolvedValue({ data, error })
  const gateway = createStructuralCatalogGateway({
    rpc,
  } as unknown as AppSupabaseClient)
  return { gateway, rpc }
}

interface GatewayCase {
  readonly label: string
  readonly rpcName: string
  readonly args: Readonly<Record<string, unknown>>
  readonly invoke: (gateway: StructuralCatalogGateway) => Promise<unknown>
}

const commandCases: readonly GatewayCase[] = [
  {
    label: 'createLocationType',
    rpcName: 'create_location_type',
    args: { code: 'TYPE', name: 'Tipo', description: null, ...rpcContext },
    invoke: (gateway) => gateway.createLocationType({
      code: 'TYPE', name: 'Tipo', description: null, ...context,
    }),
  },
  {
    label: 'updateLocationType',
    rpcName: 'update_location_type',
    args: { ...versionedArgs, code: 'TYPE', name: 'Tipo', description: null },
    invoke: (gateway) => gateway.updateLocationType({
      ...versionedInput, code: 'TYPE', name: 'Tipo', description: null,
    }),
  },
  {
    label: 'inactivateLocationType',
    rpcName: 'inactivate_location_type',
    args: versionedArgs,
    invoke: (gateway) => gateway.inactivateLocationType(versionedInput),
  },
  {
    label: 'reactivateLocationType',
    rpcName: 'reactivate_location_type',
    args: versionedArgs,
    invoke: (gateway) => gateway.reactivateLocationType(versionedInput),
  },
  {
    label: 'createLocation',
    rpcName: 'create_location',
    args: {
      location_type_id: relationId,
      parent_id: null,
      code: null,
      name: 'Local',
      description: null,
      ...rpcContext,
    },
    invoke: (gateway) => gateway.createLocation({
      locationTypeId: relationId,
      parentId: null,
      code: null,
      name: 'Local',
      description: null,
      ...context,
    }),
  },
  {
    label: 'updateLocation',
    rpcName: 'update_location',
    args: {
      ...versionedArgs,
      location_type_id: relationId,
      code: null,
      name: 'Local',
      description: null,
    },
    invoke: (gateway) => gateway.updateLocation({
      ...versionedInput,
      locationTypeId: relationId,
      code: null,
      name: 'Local',
      description: null,
    }),
  },
  {
    label: 'moveLocation',
    rpcName: 'move_location',
    args: { ...versionedArgs, parent_id: relationId },
    invoke: (gateway) => gateway.moveLocation({
      ...versionedInput, parentId: relationId,
    }),
  },
  {
    label: 'inactivateLocation',
    rpcName: 'inactivate_location',
    args: versionedArgs,
    invoke: (gateway) => gateway.inactivateLocation(versionedInput),
  },
  {
    label: 'reactivateLocation',
    rpcName: 'reactivate_location',
    args: versionedArgs,
    invoke: (gateway) => gateway.reactivateLocation(versionedInput),
  },
  {
    label: 'createCostCenter',
    rpcName: 'create_cost_center',
    args: {
      parent_id: null,
      code: 'CC',
      name: 'Centro',
      description: null,
      ...rpcContext,
    },
    invoke: (gateway) => gateway.createCostCenter({
      parentId: null,
      code: 'CC',
      name: 'Centro',
      description: null,
      ...context,
    }),
  },
  {
    label: 'updateCostCenter',
    rpcName: 'update_cost_center',
    args: { ...versionedArgs, code: 'CC', name: 'Centro', description: null },
    invoke: (gateway) => gateway.updateCostCenter({
      ...versionedInput, code: 'CC', name: 'Centro', description: null,
    }),
  },
  {
    label: 'moveCostCenter',
    rpcName: 'move_cost_center',
    args: { ...versionedArgs, parent_id: null },
    invoke: (gateway) => gateway.moveCostCenter({
      ...versionedInput, parentId: null,
    }),
  },
  {
    label: 'inactivateCostCenter',
    rpcName: 'inactivate_cost_center',
    args: versionedArgs,
    invoke: (gateway) => gateway.inactivateCostCenter(versionedInput),
  },
  {
    label: 'reactivateCostCenter',
    rpcName: 'reactivate_cost_center',
    args: versionedArgs,
    invoke: (gateway) => gateway.reactivateCostCenter(versionedInput),
  },
  {
    label: 'createSector',
    rpcName: 'create_sector',
    args: { code: null, name: 'Setor', description: null, ...rpcContext },
    invoke: (gateway) => gateway.createSector({
      code: null, name: 'Setor', description: null, ...context,
    }),
  },
  {
    label: 'updateSector',
    rpcName: 'update_sector',
    args: { ...versionedArgs, code: null, name: 'Setor', description: null },
    invoke: (gateway) => gateway.updateSector({
      ...versionedInput, code: null, name: 'Setor', description: null,
    }),
  },
  {
    label: 'inactivateSector',
    rpcName: 'inactivate_sector',
    args: versionedArgs,
    invoke: (gateway) => gateway.inactivateSector(versionedInput),
  },
  {
    label: 'reactivateSector',
    rpcName: 'reactivate_sector',
    args: versionedArgs,
    invoke: (gateway) => gateway.reactivateSector(versionedInput),
  },
]

const locationTypeListRow = {
  id, code: 'TYPE', name: 'Tipo', description: null,
  status: 'active', version: 1, updated_at: timestamp,
}
const locationListRow = {
  id, location_type_id: relationId, parent_id: null, code: null,
  name: 'Local', description: null, status: 'active', version: 1,
  updated_at: timestamp,
}
const costCenterListRow = {
  id, parent_id: null, code: 'CC', name: 'Centro', description: null,
  status: 'active', version: 1, updated_at: timestamp,
}
const sectorListRow = {
  id, code: null, name: 'Setor', description: null,
  status: 'active', version: 1, updated_at: timestamp,
}
const lookupRow = { id, code: null, name: 'Item' }

const readCases: readonly (GatewayCase & {
  readonly response: unknown
  readonly expected: unknown
})[] = [
  {
    label: 'listLocationTypes',
    rpcName: 'list_location_types',
    args: { search_text: 'tipo', status_filter: 'inactive', result_limit: 10, result_offset: 5 },
    response: [locationTypeListRow],
    expected: [locationTypeListRow],
    invoke: (gateway) => gateway.listLocationTypes({
      searchText: 'tipo', status: 'inactive', limit: 10, offset: 5,
    }),
  },
  {
    label: 'getLocationType',
    rpcName: 'get_location_type',
    args: { target_id: id },
    response: [{ ...locationTypeListRow, created_at: timestamp }],
    expected: { ...locationTypeListRow, created_at: timestamp },
    invoke: (gateway) => gateway.getLocationType(id),
  },
  {
    label: 'lookupLocationTypes',
    rpcName: 'lookup_location_types',
    args: { search_text: 'tipo', result_limit: 10 },
    response: [lookupRow],
    expected: [lookupRow],
    invoke: (gateway) => gateway.lookupLocationTypes('tipo', 10),
  },
  {
    label: 'listLocations',
    rpcName: 'list_locations',
    args: { search_text: null, status_filter: null, result_limit: 50, result_offset: 0 },
    response: [locationListRow],
    expected: [locationListRow],
    invoke: (gateway) => gateway.listLocations(),
  },
  {
    label: 'getLocation',
    rpcName: 'get_location',
    args: { target_id: id },
    response: [{ ...locationListRow, created_at: timestamp }],
    expected: { ...locationListRow, created_at: timestamp },
    invoke: (gateway) => gateway.getLocation(id),
  },
  {
    label: 'lookupLocations',
    rpcName: 'lookup_locations',
    args: { search_text: null, result_limit: 20 },
    response: [lookupRow],
    expected: [lookupRow],
    invoke: (gateway) => gateway.lookupLocations(),
  },
  {
    label: 'listLocationChildren',
    rpcName: 'list_location_children',
    args: { target_parent_id: null },
    response: [{
      id, location_type_id: relationId, parent_id: null, code: null,
      name: 'Local', status: 'active', version: 1,
    }],
    expected: [{
      id, location_type_id: relationId, parent_id: null, code: null,
      name: 'Local', status: 'active', version: 1,
    }],
    invoke: (gateway) => gateway.listLocationChildren(),
  },
  {
    label: 'listCostCenters',
    rpcName: 'list_cost_centers',
    args: { search_text: null, status_filter: null, result_limit: 50, result_offset: 0 },
    response: [costCenterListRow],
    expected: [costCenterListRow],
    invoke: (gateway) => gateway.listCostCenters(),
  },
  {
    label: 'getCostCenter',
    rpcName: 'get_cost_center',
    args: { target_id: id },
    response: [{ ...costCenterListRow, created_at: timestamp }],
    expected: { ...costCenterListRow, created_at: timestamp },
    invoke: (gateway) => gateway.getCostCenter(id),
  },
  {
    label: 'lookupCostCenters',
    rpcName: 'lookup_cost_centers',
    args: { search_text: null, result_limit: 20 },
    response: [lookupRow],
    expected: [lookupRow],
    invoke: (gateway) => gateway.lookupCostCenters(),
  },
  {
    label: 'listCostCenterChildren',
    rpcName: 'list_cost_center_children',
    args: { target_parent_id: relationId },
    response: [{
      id, parent_id: relationId, code: 'CC', name: 'Centro',
      status: 'active', version: 1,
    }],
    expected: [{
      id, parent_id: relationId, code: 'CC', name: 'Centro',
      status: 'active', version: 1,
    }],
    invoke: (gateway) => gateway.listCostCenterChildren(relationId),
  },
  {
    label: 'listSectors',
    rpcName: 'list_sectors',
    args: { search_text: null, status_filter: null, result_limit: 50, result_offset: 0 },
    response: [sectorListRow],
    expected: [sectorListRow],
    invoke: (gateway) => gateway.listSectors(),
  },
  {
    label: 'getSector',
    rpcName: 'get_sector',
    args: { target_id: id },
    response: [{ ...sectorListRow, created_at: timestamp }],
    expected: { ...sectorListRow, created_at: timestamp },
    invoke: (gateway) => gateway.getSector(id),
  },
  {
    label: 'lookupSectors',
    rpcName: 'lookup_sectors',
    args: { search_text: 'setor', result_limit: 7 },
    response: [lookupRow],
    expected: [lookupRow],
    invoke: (gateway) => gateway.lookupSectors('setor', 7),
  },
]

describe('W4A structural catalog gateway', () => {
  it.each(commandCases)('$label maps and parses its command boundary', async ({
    rpcName,
    args,
    invoke,
  }) => {
    const { gateway, rpc } = setup(commandResult)

    await expect(invoke(gateway)).resolves.toEqual(commandResult)
    expect(rpc).toHaveBeenCalledWith(rpcName, args)

    rpc.mockResolvedValueOnce({ data: commandResult, error: { message: 'denied' } })
    await expect(invoke(gateway)).rejects.toMatchObject({
      code: 'STRUCTURAL_CATALOG_UNAVAILABLE',
    })
  })

  it.each(readCases)('$label maps and parses its read boundary', async ({
    rpcName,
    args,
    response,
    expected,
    invoke,
  }) => {
    const { gateway, rpc } = setup(response)

    await expect(invoke(gateway)).resolves.toEqual(expected)
    expect(rpc).toHaveBeenCalledWith(rpcName, args)
  })

  it('exposes exactly the thirty-two approved W4A operations', () => {
    const { gateway } = setup([])
    expect(Object.keys(gateway)).toHaveLength(32)
  })

  it('rejects malformed read projections and RPC errors', async () => {
    const malformed = setup([{ ...lookupRow, status: 'active' }])
    await expect(malformed.gateway.lookupLocations()).rejects.toMatchObject({
      code: 'STRUCTURAL_CATALOG_UNAVAILABLE',
    })

    const failed = setup(null, { message: 'unavailable' })
    await expect(failed.gateway.listSectors()).rejects.toMatchObject({
      code: 'STRUCTURAL_CATALOG_UNAVAILABLE',
    })
  })
})
