import { describe, expect, it } from 'vitest'
import {
  addTeamMemberInputSchema,
  createTeamInputSchema,
  endTeamMemberInputSchema,
  myTeamSchema,
  teamCommandResultSchema,
  teamDetailSchema,
  teamForMembershipSchema,
  teamIdSchema,
  teamListInputSchema,
  teamListItemSchema,
  teamLookupInputSchema,
  teamLookupSchema,
  teamMembershipCommandResultSchema,
  teamMembershipSchema,
  teamMembersInputSchema,
  teamQueryKey,
  teamsForMembershipInputSchema,
  teamStatusCommandInputSchema,
  updateTeamInputSchema,
} from '@/shared/teams/teams'

const id = '11111111-1111-4111-8111-111111111111'
const relationId = '33333333-3333-4333-8333-333333333333'
const correlationId = '22222222-2222-4222-8222-222222222222'
const timestamp = '2026-09-17T12:00:00.000Z'
const context = {
  reason: 'alteração de equipe',
  correlationId,
  idempotencyKey: 'w4b-command-0001',
}
const listItem = {
  id,
  sector_id: null,
  code: null,
  name: 'Equipe Alfa',
  description: null,
  status: 'active',
  version: 1,
  updated_at: timestamp,
}
const membership = {
  id,
  team_id: relationId,
  membership_id: correlationId,
  user_id: '44444444-4444-4444-8444-444444444444',
  display_name: null,
  status: 'active',
  joined_at: timestamp,
  ended_at: null,
  version: 1,
}

describe('W4B team boundary', () => {
  it('accepts active/inactive teams and nullable sector and code', () => {
    expect(teamListItemSchema.parse(listItem)).toEqual(listItem)
    expect(teamDetailSchema.parse({
      ...listItem,
      status: 'inactive',
      created_at: timestamp,
    })).toMatchObject({ status: 'inactive', sector_id: null, code: null })
  })

  it('enforces active/ended membership timestamp semantics', () => {
    expect(teamMembershipSchema.parse(membership)).toEqual(membership)
    expect(teamMembershipSchema.parse({
      ...membership,
      status: 'ended',
      ended_at: timestamp,
    })).toMatchObject({ status: 'ended', ended_at: timestamp })
    expect(() => teamMembershipSchema.parse({ ...membership, ended_at: timestamp })).toThrow()
    expect(() => teamMembershipSchema.parse({ ...membership, status: 'ended' })).toThrow()
  })

  it('accepts only exact command results with command_correlation_id', () => {
    const result = { id, version: 2, status: 'active', command_correlation_id: correlationId }
    expect(teamCommandResultSchema.parse(result)).toEqual(result)
    expect(teamMembershipCommandResultSchema.parse({ ...result, status: 'ended' }))
      .toMatchObject({ status: 'ended' })
    expect(() => teamCommandResultSchema.parse({
      id,
      version: 2,
      status: 'active',
      correlation_id: correlationId,
    })).toThrow()
    expect(() => teamCommandResultSchema.parse({ ...result, extra: true })).toThrow()
  })

  it('validates all six command inputs without accepting authority payloads', () => {
    const versioned = { id, expectedVersion: 1, ...context }
    const cases = [
      [createTeamInputSchema, {
        sectorId: null, code: null, name: 'Equipe Alfa', description: null, ...context,
      }],
      [updateTeamInputSchema, {
        ...versioned, sectorId: relationId, code: 'EQ-A', name: 'Equipe Alfa', description: null,
      }],
      [teamStatusCommandInputSchema, versioned],
      [teamStatusCommandInputSchema, versioned],
      [addTeamMemberInputSchema, { teamId: id, membershipId: relationId, ...context }],
      [endTeamMemberInputSchema, versioned],
    ] as const

    for (const [schema, input] of cases) expect(schema.parse(input)).toEqual(input)
    expect(() => createTeamInputSchema.parse({
      sectorId: null,
      code: null,
      name: 'Equipe Alfa',
      description: null,
      tenantId: id,
      ...context,
    })).toThrow()
    expect(() => addTeamMemberInputSchema.parse({
      teamId: id,
      membershipId: relationId,
      actorId: id,
      scope: 'TEAM',
      ...context,
    })).toThrow()
  })

  it('rejects malformed UUIDs, versions and pagination', () => {
    expect(() => teamIdSchema.parse('not-a-uuid')).toThrow()
    expect(() => teamStatusCommandInputSchema.parse({
      id,
      expectedVersion: 0,
      ...context,
    })).toThrow()
    expect(() => teamListInputSchema.parse({ limit: 101 })).toThrow()
    expect(() => teamListInputSchema.parse({ offset: -1 })).toThrow()
  })

  it('partitions query keys by tenant, projection and filters', () => {
    expect(teamQueryKey('tenant-a', 'lookup', { search: 'alfa' })).not.toEqual(
      teamQueryKey('tenant-b', 'lookup', { search: 'alfa' }),
    )
    expect(teamQueryKey('tenant-a', 'lookup')).not.toEqual(
      teamQueryKey('tenant-a', 'roster'),
    )
  })

  it('validates the six read boundaries and keeps lookup minimal', () => {
    expect(teamListInputSchema.parse({
      searchText: 'alfa', status: 'inactive', limit: 10, offset: 2,
    })).toMatchObject({ status: 'inactive' })
    expect(teamListItemSchema.parse(listItem)).toEqual(listItem)
    expect(teamIdSchema.parse(id)).toBe(id)
    expect(teamDetailSchema.parse({ ...listItem, created_at: timestamp }))
      .toMatchObject({ id })
    expect(teamLookupInputSchema.parse({ searchText: null, limit: 20 }))
      .toEqual({ searchText: null, limit: 20 })
    expect(teamLookupSchema.parse({ id, code: null, name: 'Equipe Alfa' }))
      .toEqual({ id, code: null, name: 'Equipe Alfa' })
    expect(() => teamLookupSchema.parse({ ...listItem })).toThrow()
    expect(myTeamSchema.parse({ id, sector_id: null, code: null, name: 'Equipe Alfa' }))
      .toMatchObject({ id })
    expect(teamMembersInputSchema.parse({ teamId: id, status: 'active' }))
      .toEqual({ teamId: id, status: 'active' })
    expect(teamMembershipSchema.parse(membership)).not.toHaveProperty('email')
    expect(teamsForMembershipInputSchema.parse({
      membershipId: relationId,
      status: 'ended',
      limit: 5,
      offset: 0,
    })).toMatchObject({ membershipId: relationId, status: 'ended' })
    expect(teamForMembershipSchema.parse({
      association_id: id,
      team_id: relationId,
      sector_id: null,
      code: null,
      name: 'Equipe Alfa',
      membership_status: 'ended',
      joined_at: timestamp,
      ended_at: timestamp,
      membership_version: 2,
    })).toMatchObject({ membership_status: 'ended' })
  })
})
