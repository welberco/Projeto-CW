import { describe, expect, it } from 'vitest'
import {
  canonicalTenantPath,
  tenantRouteMatches,
} from '@/app/router/tenant-route'

const tenantRef = '34000000-0000-4000-8000-000000000001'

describe('tenant routes', () => {
  it('builds canonical routes only from a valid opaque tenant reference', () => {
    expect(canonicalTenantPath(tenantRef)).toBe(`/e/${tenantRef}/dashboard`)
    expect(canonicalTenantPath(tenantRef, 'minha-conta')).toBe(
      `/e/${tenantRef}/minha-conta`,
    )
    expect(canonicalTenantPath(tenantRef, 'manutencao/motivos')).toBe(
      `/e/${tenantRef}/manutencao/motivos`,
    )
    expect(() => canonicalTenantPath(tenantRef, '../plataforma')).toThrow()
    expect(() => canonicalTenantPath('tenant-a')).toThrow(
      'Cannot build a tenant route from an invalid reference.',
    )
  })

  it('compares the route selector with the authoritative context without granting authority', () => {
    expect(tenantRouteMatches(tenantRef.toUpperCase(), tenantRef)).toBe(true)
    expect(
      tenantRouteMatches('34000000-0000-4000-8000-000000000002', tenantRef),
    ).toBe(false)
    expect(tenantRouteMatches('invalid', tenantRef)).toBe(false)
  })
})
