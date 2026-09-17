import { describe, expect, it } from 'vitest'
import {
  costCenterInputSchema,
  locationInputSchema,
  structuralCatalogCommandContextSchema,
  structuralCatalogQueryKey,
  structuralCatalogResultSchema,
  w4aEventTypes,
} from '@/shared/catalogs/structural-catalog'

describe('W4A structural catalog contracts', () => {
  it('accepts tenant-neutral semantic catalog inputs', () => {
    expect(
      locationInputSchema.parse({
        locationTypeId: '11111111-1111-4111-8111-111111111111',
        parentId: null,
        code: 'BL-A',
        name: 'Bloco A',
        description: null,
      }),
    ).not.toHaveProperty('tenantId')

    expect(
      costCenterInputSchema.parse({
        parentId: null,
        code: 'MAN-001',
        name: 'Manutenção',
        description: 'Centro estrutural',
      }).code,
    ).toBe('MAN-001')
  })

  it('rejects mass-assignment and malformed command context', () => {
    expect(() =>
      locationInputSchema.parse({
        locationTypeId: '11111111-1111-4111-8111-111111111111',
        parentId: null,
        code: null,
        name: 'Bloco A',
        description: null,
        tenantId: '22222222-2222-4222-8222-222222222222',
      }),
    ).toThrow()

    expect(() =>
      structuralCatalogCommandContextSchema.parse({
        reason: 'criação',
        correlationId: 'not-a-uuid',
        idempotencyKey: 'short',
      }),
    ).toThrow()
  })

  it('partitions cache keys by tenant, projection and filters', () => {
    expect(
      structuralCatalogQueryKey('tenant-a', 'locations', 'lookup', {
        search: 'bloco',
      }),
    ).not.toEqual(
      structuralCatalogQueryKey('tenant-b', 'locations', 'lookup', {
        search: 'bloco',
      }),
    )
  })

  it('uses only versioned lowercase W4A event names', () => {
    expect(new Set(w4aEventTypes).size).toBe(18)
    expect(
      w4aEventTypes.every((eventType) =>
        /^cadastros\.[a-z_]+\.[a-z_]+$/.test(eventType),
      ),
    ).toBe(true)
  })

  it('accepts only the W4A command result correlation field', () => {
    expect(
      structuralCatalogResultSchema.parse({
        id: '11111111-1111-4111-8111-111111111111',
        version: 1,
        status: 'active',
        command_correlation_id: '22222222-2222-4222-8222-222222222222',
      }),
    ).toMatchObject({
      command_correlation_id: '22222222-2222-4222-8222-222222222222',
    })

    expect(() =>
      structuralCatalogResultSchema.parse({
        id: '11111111-1111-4111-8111-111111111111',
        version: 1,
        status: 'active',
        correlation_id: '22222222-2222-4222-8222-222222222222',
      }),
    ).toThrow()
  })
})
