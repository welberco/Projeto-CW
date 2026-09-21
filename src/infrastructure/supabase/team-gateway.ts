import type { ZodType } from 'zod'
import type { AppSupabaseClient } from '@/infrastructure/supabase/client'
import { AppError, type AppErrorCategory } from '@/shared/errors/app-error'
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
  teamsForMembershipInputSchema,
  teamStatusCommandInputSchema,
  updateTeamInputSchema,
  type AddTeamMemberInput,
  type CreateTeamInput,
  type EndTeamMemberInput,
  type MyTeam,
  type Team,
  type TeamCommandResult,
  type TeamForMembership,
  type TeamListInput,
  type TeamListItem,
  type TeamLookup,
  type TeamLookupInput,
  type TeamMembership,
  type TeamMembershipCommandResult,
  type TeamMembersInput,
  type TeamsForMembershipInput,
  type TeamStatusCommandInput,
  type UpdateTeamInput,
} from '@/shared/teams/teams'

export interface TeamGateway {
  createTeam(input: CreateTeamInput): Promise<TeamCommandResult>
  updateTeam(input: UpdateTeamInput): Promise<TeamCommandResult>
  inactivateTeam(input: TeamStatusCommandInput): Promise<TeamCommandResult>
  reactivateTeam(input: TeamStatusCommandInput): Promise<TeamCommandResult>
  addTeamMember(input: AddTeamMemberInput): Promise<TeamMembershipCommandResult>
  endTeamMember(input: EndTeamMemberInput): Promise<TeamMembershipCommandResult>
  listTeams(input?: TeamListInput): Promise<readonly TeamListItem[]>
  getTeam(id: string): Promise<Team | null>
  lookupTeams(input?: TeamLookupInput): Promise<readonly TeamLookup[]>
  listMyTeams(): Promise<readonly MyTeam[]>
  listTeamMembers(input: TeamMembersInput): Promise<readonly TeamMembership[]>
  listTeamsForMembership(input: TeamsForMembershipInput): Promise<readonly TeamForMembership[]>
}

type RpcRequest = PromiseLike<{ data: unknown; error: unknown }>

interface RpcErrorShape {
  readonly code?: unknown
  readonly message?: unknown
}

function domainError(error: unknown): AppError {
  const rpcError = error as RpcErrorShape | null
  const sqlState = typeof rpcError?.code === 'string' ? rpcError.code : undefined
  const message = typeof rpcError?.message === 'string' ? rpcError.message : undefined
  const domainCode = message?.match(/\b[A-Z][A-Z0-9_]+\b/)?.[0]
  const code = domainCode ?? 'TEAM_BOUNDARY_UNAVAILABLE'
  let category: AppErrorCategory = 'unavailable'

  if (sqlState === '42501' || code === 'AUTHORIZATION_DENIED') category = 'forbidden'
  else if (code.includes('VERSION_CONFLICT') || code.includes('IDEMPOTENCY_CONFLICT')) {
    category = 'conflict'
  } else if (code.includes('STATE')) category = 'invalid_state'
  else if (sqlState === '22023' || code.startsWith('INVALID_')) category = 'validation'

  return new AppError({
    code,
    category,
    userMessage: 'Não foi possível concluir a operação de equipe com segurança.',
    cause: error,
  })
}

function invalidResponse(cause: unknown): AppError {
  return new AppError({
    code: 'TEAM_BOUNDARY_INVALID_RESPONSE',
    category: 'unavailable',
    userMessage: 'A resposta do cadastro de equipes é inválida.',
    cause,
  })
}

async function parseRpc<T>(request: RpcRequest, schema: ZodType<T>): Promise<T> {
  const { data, error } = await request
  if (error !== null) throw domainError(error)
  const parsed = schema.safeParse(data)
  if (!parsed.success) throw invalidResponse(parsed.error)
  return parsed.data
}

function command<T>(request: RpcRequest, schema: ZodType<T>): Promise<T> {
  return parseRpc(request, schema)
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

function contextArgs(input: {
  readonly reason: string
  readonly correlationId: string
  readonly idempotencyKey: string
}) {
  return {
    reason: input.reason,
    correlation_id: input.correlationId,
    idempotency_key: input.idempotencyKey,
  }
}

function versionedArgs(input: TeamStatusCommandInput) {
  return {
    id: input.id,
    expected_version: input.expectedVersion,
    ...contextArgs(input),
  }
}

export function createTeamGateway(client: AppSupabaseClient): TeamGateway {
  return {
    createTeam(rawInput) {
      const input = createTeamInputSchema.parse(rawInput)
      return command(client.rpc('create_team', {
        sector_id: sqlNullable(input.sectorId),
        code: sqlNullable(input.code),
        name: input.name,
        description: sqlNullable(input.description),
        ...contextArgs(input),
      }), teamCommandResultSchema)
    },
    updateTeam(rawInput) {
      const input = updateTeamInputSchema.parse(rawInput)
      return command(client.rpc('update_team', {
        ...versionedArgs(input),
        sector_id: sqlNullable(input.sectorId),
        code: sqlNullable(input.code),
        name: input.name,
        description: sqlNullable(input.description),
      }), teamCommandResultSchema)
    },
    inactivateTeam(rawInput) {
      const input = teamStatusCommandInputSchema.parse(rawInput)
      return command(
        client.rpc('inactivate_team', versionedArgs(input)),
        teamCommandResultSchema,
      )
    },
    reactivateTeam(rawInput) {
      const input = teamStatusCommandInputSchema.parse(rawInput)
      return command(
        client.rpc('reactivate_team', versionedArgs(input)),
        teamCommandResultSchema,
      )
    },
    addTeamMember(rawInput) {
      const input = addTeamMemberInputSchema.parse(rawInput)
      return command(client.rpc('add_team_member', {
        team_id: input.teamId,
        membership_id: input.membershipId,
        ...contextArgs(input),
      }), teamMembershipCommandResultSchema)
    },
    endTeamMember(rawInput) {
      const input = endTeamMemberInputSchema.parse(rawInput)
      return command(
        client.rpc('end_team_member', versionedArgs(input)),
        teamMembershipCommandResultSchema,
      )
    },
    listTeams(rawInput = {}) {
      const input = teamListInputSchema.parse(rawInput)
      return rows(client.rpc('list_teams', {
        search_text: sqlNullable(input.searchText ?? null),
        status_filter: sqlNullable(input.status ?? null),
        result_limit: input.limit ?? 50,
        result_offset: input.offset ?? 0,
      }), teamListItemSchema)
    },
    getTeam(rawId) {
      const id = teamIdSchema.parse(rawId)
      return detail(client.rpc('get_team', { target_id: id }), teamDetailSchema)
    },
    lookupTeams(rawInput = {}) {
      const input = teamLookupInputSchema.parse(rawInput)
      return rows(client.rpc('lookup_teams', {
        search_text: sqlNullable(input.searchText ?? null),
        result_limit: input.limit ?? 20,
      }), teamLookupSchema)
    },
    listMyTeams() {
      return rows(client.rpc('list_my_teams'), myTeamSchema)
    },
    listTeamMembers(rawInput) {
      const input = teamMembersInputSchema.parse(rawInput)
      return rows(client.rpc('list_team_members', {
        target_team_id: input.teamId,
        status_filter: sqlNullable(input.status ?? null),
        result_limit: input.limit ?? 50,
        result_offset: input.offset ?? 0,
      }), teamMembershipSchema)
    },
    listTeamsForMembership(rawInput) {
      const input = teamsForMembershipInputSchema.parse(rawInput)
      return rows(client.rpc('list_teams_for_membership', {
        target_membership_id: input.membershipId,
        status_filter: sqlNullable(input.status ?? null),
        result_limit: input.limit ?? 50,
        result_offset: input.offset ?? 0,
      }), teamForMembershipSchema)
    },
  }
}
