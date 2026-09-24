import { z } from 'zod'

export const teamStatusSchema = z.enum(['active', 'inactive'])
export type TeamStatus = z.infer<typeof teamStatusSchema>

export const teamMembershipStatusSchema = z.enum(['active', 'ended'])
export type TeamMembershipStatus = z.infer<typeof teamMembershipStatusSchema>

const uuidSchema = z.string().uuid()
const versionSchema = z.number().int().positive()
const timestampSchema = z.string().datetime({ offset: true })
const codeSchema = z
  .string()
  .trim()
  .min(1)
  .max(64)
  .regex(/^[A-Za-z0-9][A-Za-z0-9._/-]*$/)
const nullableCodeSchema = codeSchema.nullable()
const nameSchema = z.string().trim().min(1).max(160)
const descriptionSchema = z.string().trim().max(2_000).nullable()
const displayNameSchema = z.string().trim().min(1).max(160).nullable()
const searchTextSchema = z.string().trim().max(160).nullable().optional()
const limitSchema = z.number().int().min(1).max(100).optional()
const offsetSchema = z.number().int().nonnegative().optional()

export const teamCommandResultSchema = z
  .object({
    id: uuidSchema,
    version: versionSchema,
    status: teamStatusSchema,
    command_correlation_id: uuidSchema,
  })
  .strict()

export const teamMembershipCommandResultSchema = z
  .object({
    id: uuidSchema,
    version: versionSchema,
    status: teamMembershipStatusSchema,
    command_correlation_id: uuidSchema,
  })
  .strict()

const teamListBaseSchema = z.object({
  id: uuidSchema,
  sector_id: uuidSchema.nullable(),
  code: nullableCodeSchema,
  name: nameSchema,
  description: descriptionSchema,
  status: teamStatusSchema,
  version: versionSchema,
  updated_at: timestampSchema,
})

export const teamListItemSchema = teamListBaseSchema.strict()
export const teamDetailSchema = teamListBaseSchema
  .extend({ created_at: timestampSchema })
  .strict()

export const teamLookupSchema = z
  .object({ id: uuidSchema, code: nullableCodeSchema, name: nameSchema })
  .strict()

export const myTeamSchema = z
  .object({
    id: uuidSchema,
    sector_id: uuidSchema.nullable(),
    code: nullableCodeSchema,
    name: nameSchema,
  })
  .strict()

export const teamMembershipSchema = z
  .object({
    id: uuidSchema,
    team_id: uuidSchema,
    membership_id: uuidSchema,
    user_id: uuidSchema,
    display_name: displayNameSchema,
    status: teamMembershipStatusSchema,
    joined_at: timestampSchema,
    ended_at: timestampSchema.nullable(),
    version: versionSchema,
  })
  .strict()
  .superRefine((membership, context) => {
    if (membership.status === 'active' && membership.ended_at !== null) {
      context.addIssue({
        code: 'custom',
        path: ['ended_at'],
        message: 'Active team membership cannot have ended_at.',
      })
    }
    if (membership.status === 'ended' && membership.ended_at === null) {
      context.addIssue({
        code: 'custom',
        path: ['ended_at'],
        message: 'Ended team membership requires ended_at.',
      })
    }
  })

export const teamMemberCandidateSchema = z
  .object({
    membership_id: uuidSchema,
    user_id: uuidSchema,
    display_name: displayNameSchema,
  })
  .strict()

export const teamForMembershipSchema = z
  .object({
    association_id: uuidSchema,
    team_id: uuidSchema,
    sector_id: uuidSchema.nullable(),
    code: nullableCodeSchema,
    name: nameSchema,
    membership_status: teamMembershipStatusSchema,
    joined_at: timestampSchema,
    ended_at: timestampSchema.nullable(),
    membership_version: versionSchema,
  })
  .strict()
  .superRefine((association, context) => {
    if (association.membership_status === 'active' && association.ended_at !== null) {
      context.addIssue({
        code: 'custom',
        path: ['ended_at'],
        message: 'Active team membership cannot have ended_at.',
      })
    }
    if (association.membership_status === 'ended' && association.ended_at === null) {
      context.addIssue({
        code: 'custom',
        path: ['ended_at'],
        message: 'Ended team membership requires ended_at.',
      })
    }
  })

export type TeamCommandResult = z.infer<typeof teamCommandResultSchema>
export type TeamMembershipCommandResult = z.infer<typeof teamMembershipCommandResultSchema>
export type Team = z.infer<typeof teamDetailSchema>
export type TeamListItem = z.infer<typeof teamListItemSchema>
export type TeamLookup = z.infer<typeof teamLookupSchema>
export type MyTeam = z.infer<typeof myTeamSchema>
export type TeamMembership = z.infer<typeof teamMembershipSchema>
export type TeamMemberCandidate = z.infer<typeof teamMemberCandidateSchema>
export type TeamForMembership = z.infer<typeof teamForMembershipSchema>

export const teamCommandContextSchema = z
  .object({
    reason: z.string().trim().min(1).max(500),
    correlationId: uuidSchema,
    idempotencyKey: z
      .string()
      .min(8)
      .max(200)
      .regex(/^[A-Za-z0-9][A-Za-z0-9._:-]*$/),
  })
  .strict()

const versionedCommandSchema = z.object({
  id: uuidSchema,
  expectedVersion: versionSchema,
  ...teamCommandContextSchema.shape,
})

export const createTeamInputSchema = z
  .object({
    sectorId: uuidSchema.nullable(),
    code: nullableCodeSchema,
    name: nameSchema,
    description: descriptionSchema,
    ...teamCommandContextSchema.shape,
  })
  .strict()

export const updateTeamInputSchema = z
  .object({
    ...versionedCommandSchema.shape,
    sectorId: uuidSchema.nullable(),
    code: nullableCodeSchema,
    name: nameSchema,
    description: descriptionSchema,
  })
  .strict()

export const teamStatusCommandInputSchema = versionedCommandSchema.strict()

export const addTeamMemberInputSchema = z
  .object({
    teamId: uuidSchema,
    membershipId: uuidSchema,
    ...teamCommandContextSchema.shape,
  })
  .strict()

export const endTeamMemberInputSchema = versionedCommandSchema.strict()

export const teamListInputSchema = z
  .object({
    searchText: searchTextSchema,
    status: teamStatusSchema.nullable().optional(),
    limit: limitSchema,
    offset: offsetSchema,
  })
  .strict()

export const teamLookupInputSchema = z
  .object({ searchText: searchTextSchema, limit: limitSchema })
  .strict()

export const teamMembersInputSchema = z
  .object({
    teamId: uuidSchema,
    status: teamMembershipStatusSchema.nullable().optional(),
    limit: limitSchema,
    offset: offsetSchema,
  })
  .strict()

export const teamsForMembershipInputSchema = z
  .object({
    membershipId: uuidSchema,
    status: teamMembershipStatusSchema.nullable().optional(),
    limit: limitSchema,
    offset: offsetSchema,
  })
  .strict()

export const teamIdSchema = uuidSchema

export const teamMemberCandidateLookupInputSchema = z
  .object({
    teamId: uuidSchema,
    searchText: searchTextSchema,
    limit: limitSchema,
    offset: offsetSchema,
  })
  .strict()
export type TeamMemberCandidateLookupInput = z.infer<typeof teamMemberCandidateLookupInputSchema>

export type CreateTeamInput = z.infer<typeof createTeamInputSchema>
export type UpdateTeamInput = z.infer<typeof updateTeamInputSchema>
export type TeamStatusCommandInput = z.infer<typeof teamStatusCommandInputSchema>
export type AddTeamMemberInput = z.infer<typeof addTeamMemberInputSchema>
export type EndTeamMemberInput = z.infer<typeof endTeamMemberInputSchema>
export type TeamListInput = z.infer<typeof teamListInputSchema>
export type TeamLookupInput = z.infer<typeof teamLookupInputSchema>
export type TeamMembersInput = z.infer<typeof teamMembersInputSchema>
export type TeamsForMembershipInput = z.infer<typeof teamsForMembershipInputSchema>

export type TeamQueryProjection =
  | 'admin'
  | 'detail'
  | 'lookup'
  | 'my-teams'
  | 'roster'
  | 'membership-teams'

export function teamQueryKey(
  tenantId: string,
  projection: TeamQueryProjection,
  filters: Readonly<Record<string, string | number | null>> = {},
): readonly unknown[] {
  return ['tenant', tenantId, 'teams', projection, filters] as const
}
