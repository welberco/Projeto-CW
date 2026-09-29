import { describe, expect, it } from 'vitest'

import {
  assetLookupSchema,
  assetOperationalConditionSchema,
  assetPermissionCodes,
  assetRegistrationStatusSchema,
  assetSpecificationDefinitionSchema,
  assetTypeLookupSchema,
} from './assets'

const id = '10000000-0000-4000-8000-000000000001'

describe('W5A Asset contracts', () => {
  it('freezes exactly fourteen Asset and Asset Type permissions', () => {
    expect(assetPermissionCodes).toEqual([
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
    ])
    expect(new Set(assetPermissionCodes).size).toBe(14)
  })

  it('freezes registration and operational vocabularies', () => {
    expect(assetRegistrationStatusSchema.options).toEqual([
      'ACTIVE',
      'INACTIVE',
      'DECOMMISSIONED',
    ])
    expect(assetOperationalConditionSchema.options).toEqual([
      'OPERATIONAL',
      'PARTIAL',
      'UNDER_MAINTENANCE',
      'OUT_OF_OPERATION',
    ])
  })

  it('accepts only the narrow Requester Asset lookup projection', () => {
    const lookup = {
      id,
      code: 'AT-00001',
      name: 'Bomba principal',
      registration_status: 'ACTIVE',
      operational_condition: 'OPERATIONAL',
    }

    expect(assetLookupSchema.parse(lookup)).toEqual(lookup)
    expect(
      assetLookupSchema.safeParse({ ...lookup, specifications: {} }).success,
    ).toBe(false)
    expect(assetLookupSchema.safeParse({ ...lookup, storage_key: 'v1/x' }).success).toBe(false)
    expect(assetLookupSchema.safeParse({ ...lookup, sha256: 'secret' }).success).toBe(false)
  })

  it('accepts only id and name in the Asset Type lookup', () => {
    expect(assetTypeLookupSchema.parse({ id, name: 'Bomba' })).toEqual({
      id,
      name: 'Bomba',
    })
    expect(assetTypeLookupSchema.safeParse({ id, name: 'Bomba', code: 'BOMBA' }).success).toBe(false)
    expect(assetTypeLookupSchema.safeParse({ id, name: 'Bomba', fields: [] }).success).toBe(false)
  })

  it('validates the closed specification meta-schema v1', () => {
    const definition = {
      definition_schema_version: 1,
      asset_type_id: id,
      revision: 1,
      fields: [
        {
          key: 'serial_number',
          label: 'Número de série',
          type: 'STRING',
          required: true,
          nullable: false,
          min_length: 1,
          max_length: 80,
        },
        {
          key: 'phase',
          label: 'Fase',
          type: 'ENUM',
          required: false,
          nullable: true,
          options: ['MONO', 'TRI'],
        },
      ],
    }

    expect(assetSpecificationDefinitionSchema.safeParse(definition).success).toBe(true)
    expect(
      assetSpecificationDefinitionSchema.safeParse({
        ...definition,
        definition_schema_version: 2,
      }).success,
    ).toBe(false)
    expect(
      assetSpecificationDefinitionSchema.safeParse({
        ...definition,
        fields: [...definition.fields, definition.fields[0]],
      }).success,
    ).toBe(false)
    expect(
      assetSpecificationDefinitionSchema.safeParse({
        ...definition,
        fields: [
          {
            key: 'enabled',
            label: 'Habilitado',
            type: 'BOOLEAN',
            required: true,
            nullable: false,
            minimum: 0,
          },
        ],
      }).success,
    ).toBe(false)
    expect(
      assetSpecificationDefinitionSchema.safeParse({
        ...definition,
        fields: [
          {
            key: 'serial_number',
            label: 'Número de série',
            type: 'STRING',
            required: true,
            nullable: false,
            pattern: '^[A-Z]+$',
          },
        ],
      }).success,
    ).toBe(false)
  })
})
