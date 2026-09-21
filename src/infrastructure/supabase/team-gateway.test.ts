import { describe, expect, it, vi } from 'vitest'
import type { AppSupabaseClient } from '@/infrastructure/supabase/client'
import {
  createTeamGateway,
  type TeamGateway,
} from '@/infrastructure/supabase/team-gateway'

const id = '11111111-1111-4111-8111-111111111111'
const membershipId = '33333333-3333-4333-8333-333333333333'
const correlationId = '22222222-2222-4222-8222-222222222222'
const userId = '44444444-4444-4444-8444-444444444444'
const timestamp = '2026-09-17T12:00:00.000Z'
const context = {
  reason: 'alteração de equipe',
  correlationId,
  idempotencyKey: 'w4b-command-0001',
}
const rpcContext = {
  reason: context.reason,
  correlation_id: correlationId,
  idempotency_key: context.idempotencyKey,
}
const versionedInput = { id, expectedVersion: 1, ...context }
const versionedArgs = { id, expected_version: 1, ...rpcContext }
const teamResult = { id, version: 2, status: 'active', command_correlation_id: correlationId }
const membershipResult = {
  id,
  version: 2,
  status: 'active',
  command_correlation_id: correlationId,
}

function setup(data: unknown, error: unknown = null) {
  const rpc = vi.fn().mockResolvedValue({ data, error })
  const from = vi.fn()
  const gateway = createTeamGateway({ rpc, from } as unknown as AppSupabaseClient)
  return { gateway, rpc, from }
}

interface GatewayCase {
  readonly label: string
  readonly rpcName: string
  readonly args?: Readonly<Record<string, unknown>>
  readonly response: unknown
  readonly expected: unknown
  readonly invoke: (gateway: TeamGateway) => Promise<unknown>
}

const commandCases: readonly GatewayCase[] = [
  {
    label: 'createTeam',
    rpcName: 'create_team',
    args: {
      sector_id: null,
      code: null,
      name: 'Equipe Alfa',
      description: null,
      ...rpcContext,
    },
    response: teamResult,
    expected: teamResult,
    invoke: (gateway) => gateway.createTeam({
      sectorId: null,
      code: null,
      name: 'Equipe Alfa',
      description: null,
      ...context,
    }),
  },
  {
    label: 'updateTeam',
    rpcName: 'update_team',
    args: {
      ...versionedArgs,
      sector_id: membershipId,
      code: 'EQ-A',
      name: 'Equipe Alfa',
      description: null,
    },
    response: teamResult,
    expected: teamResult,
    invoke: (gateway) => gateway.updateTeam({
      ...versionedInput,
      sectorId: membershipId,
      code: 'EQ-A',
      name: 'Equipe Alfa',
      description: null,
    }),
  },
  {
    label: 'inactivateTeam',
    rpcName: 'inactivate_team',
    args: versionedArgs,
    response: { ...teamResult, status: 'inactive' },
    expected: { ...teamResult, status: 'inactive' },
    invoke: (gateway) => gateway.inactivateTeam(versionedInput),
  },
  {
    label: 'reactivateTeam',
    rpcName: 'reactivate_team',
    args: versionedArgs,
    response: teamResult,
    expected: teamResult,
    invoke: (gateway) => gateway.reactivateTeam(versionedInput),
  },
  {
    label: 'addTeamMember',
    rpcName: 'add_team_member',
    args: { team_id: id, membership_id: membershipId, ...rpcContext },
    response: membershipResult,
    expected: membershipResult,
    invoke: (gateway) => gateway.addTeamMember({ teamId: id, membershipId, ...context }),
  },
  {
    label: 'endTeamMember',
    rpcName: 'end_team_member',
    args: versionedArgs,
    response: { ...membershipResult, status: 'ended' },
    expected: { ...membershipResult, status: 'ended' },
    invoke: (gateway) => gateway.endTeamMember(versionedInput),
  },
]

const listRow = {
  id,
  sector_id: null,
  code: null,
  name: 'Equipe Alfa',
  description: null,
  status: 'active',
  version: 1,
  updated_at: timestamp,
}
const lookupRow = { id, code: null, name: 'Equipe Alfa' }
const rosterRow = {
  id,
  team_id: membershipId,
  membership_id: correlationId,
  user_id: userId,
  display_name: null,
  status: 'active',
  joined_at: timestamp,
  ended_at: null,
  version: 1,
}
const teamForMembershipRow = {
  association_id: id,
  team_id: membershipId,
  sector_id: null,
  code: null,
  name: 'Equipe Alfa',
  membership_status: 'active',
  joined_at: timestamp,
  ended_at: null,
  membership_version: 1,
}

const readCases: readonly GatewayCase[] = [
  {
    label: 'listTeams',
    rpcName: 'list_teams',
    args: { search_text: 'alfa', status_filter: 'active', result_limit: 10, result_offset: 2 },
    response: [listRow],
    expected: [listRow],
    invoke: (gateway) => gateway.listTeams({
      searchText: 'alfa', status: 'active', limit: 10, offset: 2,
    }),
  },
  {
    label: 'getTeam',
    rpcName: 'get_team',
    args: { target_id: id },
    response: [{ ...listRow, created_at: timestamp }],
    expected: { ...listRow, created_at: timestamp },
    invoke: (gateway) => gateway.getTeam(id),
  },
  {
    label: 'lookupTeams',
    rpcName: 'lookup_teams',
    args: { search_text: null, result_limit: 20 },
    response: [lookupRow],
    expected: [lookupRow],
    invoke: (gateway) => gateway.lookupTeams(),
  },
  {
    label: 'listMyTeams',
    rpcName: 'list_my_teams',
    response: [{ ...lookupRow, sector_id: null }],
    expected: [{ ...lookupRow, sector_id: null }],
    invoke: (gateway) => gateway.listMyTeams(),
  },
  {
    label: 'listTeamMembers',
    rpcName: 'list_team_members',
    args: {
      target_team_id: id,
      status_filter: null,
      result_limit: 50,
      result_offset: 0,
    },
    response: [rosterRow],
    expected: [rosterRow],
    invoke: (gateway) => gateway.listTeamMembers({ teamId: id }),
  },
  {
    label: 'listTeamsForMembership',
    rpcName: 'list_teams_for_membership',
    args: {
      target_membership_id: membershipId,
      status_filter: 'active',
      result_limit: 5,
      result_offset: 1,
    },
    response: [teamForMembershipRow],
    expected: [teamForMembershipRow],
    invoke: (gateway) => gateway.listTeamsForMembership({
      membershipId, status: 'active', limit: 5, offset: 1,
    }),
  },
]

describe('W4B team gateway', () => {
  it.each(commandCases)('$label maps and parses its command boundary', async ({
    rpcName,
    args,
    response,
    expected,
    invoke,
  }) => {
    const { gateway, rpc, from } = setup(response)
    await expect(invoke(gateway)).resolves.toEqual(expected)
    expect(rpc).toHaveBeenCalledWith(rpcName, args)
    expect(from).not.toHaveBeenCalled()
  })

  it.each(readCases)('$label maps and parses its read boundary', async ({
    rpcName,
    args,
    response,
    expected,
    invoke,
  }) => {
    const { gateway, rpc, from } = setup(response)
    await expect(invoke(gateway)).resolves.toEqual(expected)
    if (args === undefined) expect(rpc).toHaveBeenCalledWith(rpcName)
    else expect(rpc).toHaveBeenCalledWith(rpcName, args)
    expect(from).not.toHaveBeenCalled()
  })

  it('exposes exactly the twelve approved operations', () => {
    const { gateway } = setup([])
    expect(Object.keys(gateway)).toEqual([
      'createTeam',
      'updateTeam',
      'inactivateTeam',
      'reactivateTeam',
      'addTeamMember',
      'endTeamMember',
      'listTeams',
      'getTeam',
      'lookupTeams',
      'listMyTeams',
      'listTeamMembers',
      'listTeamsForMembership',
    ])
  })

  it('rejects malformed and expanded projections', async () => {
    const legacy = setup([{ ...lookupRow, description: 'not allowed' }])
    await expect(legacy.gateway.lookupTeams()).rejects.toMatchObject({
      code: 'TEAM_BOUNDARY_INVALID_RESPONSE',
    })

    const legacyCommand = setup({
      id,
      version: 1,
      status: 'active',
      correlation_id: correlationId,
    })
    await expect(legacyCommand.gateway.createTeam({
      sectorId: null,
      code: null,
      name: 'Equipe Alfa',
      description: null,
      ...context,
    })).rejects.toMatchObject({ code: 'TEAM_BOUNDARY_INVALID_RESPONSE' })
  })

  it('preserves authorization, concurrency and invalid-state failures', async () => {
    const authorization = setup(null, { code: '42501', message: 'AUTHORIZATION_DENIED' })
    await expect(authorization.gateway.listTeams()).rejects.toMatchObject({
      code: 'AUTHORIZATION_DENIED',
      category: 'forbidden',
    })

    const conflict = setup(null, { code: 'P0001', message: 'TEAM_VERSION_CONFLICT' })
    await expect(conflict.gateway.inactivateTeam(versionedInput)).rejects.toMatchObject({
      code: 'TEAM_VERSION_CONFLICT',
      category: 'conflict',
    })

    const state = setup(null, {
      code: 'P0001',
      message: 'TEAM_MEMBERSHIP_STATE_OR_VERSION_CONFLICT',
    })
    await expect(state.gateway.endTeamMember(versionedInput)).rejects.toMatchObject({
      code: 'TEAM_MEMBERSHIP_STATE_OR_VERSION_CONFLICT',
      category: 'conflict',
    })
  })

  it('rejects invalid format and invented authority before calling the RPC', () => {
    const { gateway, rpc } = setup(teamResult)
    expect(() => gateway.getTeam('not-a-uuid')).toThrow()
    expect(() => gateway.listTeams({ limit: 0 })).toThrow()
    expect(() => gateway.createTeam({
      sectorId: null,
      code: null,
      name: 'Equipe Alfa',
      description: null,
      tenantId: id,
      actorId: membershipId,
      scope: 'TEAM',
      ...context,
    } as never)).toThrow()
    expect(rpc).not.toHaveBeenCalled()
  })

  it('preserves anti-enumeration as an empty detail result', async () => {
    const { gateway } = setup([])
    await expect(gateway.getTeam(id)).resolves.toBeNull()
  })
})
