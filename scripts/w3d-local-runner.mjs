import { randomUUID } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { z } from 'zod'
import { createHandlerRegistry } from '../src/shared/events/event-contract.ts'

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const config = readFileSync(path.join(projectRoot, 'supabase', 'config.toml'), 'utf8')
const projectId = /^project_id\s*=\s*"([a-z0-9-]+)"\s*$/mu.exec(config)?.[1]

if (projectId === undefined) {
  throw new Error('W3D_RUNNER_BLOCKER: projeto Supabase local não identificado.')
}

const containerName = `supabase_db_${projectId}`
const identifierPattern = /^[a-z][a-z0-9_.:-]{2,159}$/u
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`
}

function runWorkerSql(sql) {
  const result = spawnSync(
    'docker',
    [
      'exec', '-i', containerName, 'psql', '-X', '-q', '-A', '-t',
      '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres', '-c',
      `set role cw_worker; ${sql}`,
    ],
    { cwd: projectRoot, encoding: 'utf8', stdio: 'pipe' },
  )

  if (result.error !== undefined || result.status !== 0) {
    throw new Error(
      `W3D_RUNNER_DATABASE_ERROR: ${result.error?.message ?? result.stderr.trim()}`,
    )
  }

  return result.stdout.trim()
}

function parseJsonOutput(output, fallback) {
  if (output.length === 0) return fallback
  return JSON.parse(output.split(/\r?\n/u).at(-1))
}

function assertClaimIdentity(claim) {
  for (const value of [claim.event_id, claim.tenant_id, claim.lease_token]) {
    if (typeof value !== 'string' || !uuidPattern.test(value)) {
      throw new Error('W3D_RUNNER_INVALID_CLAIM_IDENTITY')
    }
  }
  if (
    typeof claim.claimed_by !== 'string' ||
    !identifierPattern.test(claim.claimed_by) ||
    !Number.isSafeInteger(claim.fencing_token)
  ) {
    throw new Error('W3D_RUNNER_INVALID_CLAIM_FENCE')
  }
}

function readProfileOrigin(event, context) {
  const output = runWorkerSql(`
    select row_to_json(origin)::text
    from public.read_profile_created_origin(
      ${sqlLiteral(event.eventId)}::uuid,
      ${sqlLiteral(context.technicalActorRef)},
      ${sqlLiteral(context.leaseToken)}::uuid,
      ${context.fencingToken}::bigint
    ) as origin;
  `)
  const origin = parseJsonOutput(output, null)
  if (origin === null) throw new Error('W3D_RUNNER_ORIGIN_UNAVAILABLE')
  return origin
}

function createRegistry(failureInjectionEventIds = new Set()) {
  const payloadSchema = z.object({ profile_version: z.number().int().positive() }).strict()
  const handler = {
    handlerName: 'authorization_profile_created_v1',
    handlerVersion: 1,
    capability: 'authorization.profile.read',
    async handle(event, context) {
      // Local integration hook only; event/payload never selects this behavior.
      if (failureInjectionEventIds.has(event.eventId)) {
        return { status: 'retryable_failure', code: 'INJECTED_TRANSIENT_FAILURE' }
      }
      if (
        event.aggregate?.type !== 'tenant_profile' ||
        event.aggregate.id.length === 0 ||
        event.aggregate.version !== event.payload.profile_version
      ) {
        return { status: 'terminal_failure', code: 'EVENT_AGGREGATE_INVALID' }
      }

      const origin = readProfileOrigin(event, context)
      if (
        origin.authoritative_tenant_id !== context.tenantId ||
        origin.authoritative_profile_id !== event.aggregate.id
      ) {
        return { status: 'terminal_failure', code: 'EVENT_ORIGIN_MISMATCH' }
      }

      return {
        status: 'processed',
        result: {
          observed_profile_version: origin.authoritative_profile_version,
          observed_profile_status: origin.authoritative_profile_status,
        },
      }
    },
  }

  return createHandlerRegistry([
    {
      eventType: 'authorization.profile.created',
      eventVersion: 1,
      payloadSchema,
      handler,
    },
  ])
}

function toEnvelope(claim) {
  return {
    event: {
      eventId: claim.event_id,
      eventType: claim.event_type,
      eventVersion: claim.event_version,
      occurredAt: claim.occurred_at,
      scope: { kind: 'tenant', tenantId: claim.tenant_id },
      commandId: claim.command_id,
      correlationId: claim.correlation_id,
      ...(claim.causation_id === null ? {} : { causationId: claim.causation_id }),
      ...(claim.aggregate_id === null
        ? {}
        : {
            aggregate: {
              type: claim.aggregate_type,
              id: claim.aggregate_id,
              ...(claim.aggregate_version === null
                ? {}
                : { version: claim.aggregate_version }),
            },
          }),
      payload: claim.payload,
      metadata: claim.metadata,
    },
    delivery: {
      status: 'processing',
      attemptCount: claim.attempt_count,
      nextAttemptAt: claim.lease_expires_at,
      claimedBy: claim.claimed_by,
      leaseExpiresAt: claim.lease_expires_at,
      leaseToken: claim.lease_token,
      fencingToken: claim.fencing_token,
    },
  }
}

function classifyFailure(result) {
  if (result.status === 'retryable_failure') {
    return ['retryable', result.code, 'Allowlisted handler reported a retryable failure.']
  }
  if (result.code === 'EVENT_CONTRACT_UNSUPPORTED') {
    return ['unsupported_event', result.code, 'Event contract is not allowlisted.']
  }
  if (result.code === 'EVENT_PAYLOAD_INVALID') {
    return ['poison_event', result.code, 'Persisted event payload failed schema validation.']
  }
  return ['non_retryable', result.code, 'Allowlisted handler rejected the persisted event.']
}

export function claimBatch(workerIdentity, batchSize = 10) {
  if (!identifierPattern.test(workerIdentity)) throw new Error('W3D_RUNNER_INVALID_WORKER')
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 100) {
    throw new Error('W3D_RUNNER_INVALID_BATCH')
  }

  const output = runWorkerSql(`
    select coalesce(pg_catalog.json_agg(pg_catalog.row_to_json(claimed)), '[]'::json)::text
    from public.claim_outbox_batch(${sqlLiteral(workerIdentity)}, ${batchSize}) as claimed;
  `)
  return parseJsonOutput(output, [])
}

export async function processOnce(options = {}) {
  const workerIdentity = options.workerIdentity ?? `local:w3d-${randomUUID()}`
  const batchSize = options.batchSize ?? 10
  const registry = createRegistry(options.failureInjectionEventIds ?? new Set())
  const claims = claimBatch(workerIdentity, batchSize)
  const summary = { claimed: claims.length, processed: 0, failed: 0, replayed: 0 }

  for (const claim of claims) {
    assertClaimIdentity(claim)
    if (
      claim.consumer_name !== 'cw.authorization.profile_projection' ||
      claim.handler_name !== 'authorization_profile_created_v1' ||
      claim.handler_version !== 1
    ) {
      runWorkerSql(`
        select * from public.fail_outbox_event(
          ${sqlLiteral(claim.event_id)}::uuid,
          ${sqlLiteral(workerIdentity)},
          ${sqlLiteral(claim.lease_token)}::uuid,
          ${claim.fencing_token}::bigint,
          'unsupported_event', 'HANDLER_CONTROL_UNSUPPORTED',
          'Handler control does not match the compiled allowlist.'
        );
      `)
      summary.failed += 1
      continue
    }
    const result = await registry.dispatch(toEnvelope(claim), {
      consumerName: claim.consumer_name,
      technicalActorRef: workerIdentity,
      tenantId: claim.tenant_id,
      correlationId: claim.correlation_id,
      leaseToken: claim.lease_token,
      fencingToken: claim.fencing_token,
    })

    if (result.status === 'processed' || result.status === 'duplicate') {
      const output = runWorkerSql(`
        select row_to_json(completed)::text
        from public.complete_outbox_event(
          ${sqlLiteral(claim.event_id)}::uuid,
          ${sqlLiteral(workerIdentity)},
          ${sqlLiteral(claim.lease_token)}::uuid,
          ${claim.fencing_token}::bigint,
          1,
          ${sqlLiteral(JSON.stringify(result.result))}::jsonb
        ) as completed;
      `)
      const completed = parseJsonOutput(output, null)
      summary.processed += 1
      if (completed?.receipt_replayed === true) summary.replayed += 1
      continue
    }

    const [failureClass, code, message] = classifyFailure(result)
    runWorkerSql(`
      select * from public.fail_outbox_event(
        ${sqlLiteral(claim.event_id)}::uuid,
        ${sqlLiteral(workerIdentity)},
        ${sqlLiteral(claim.lease_token)}::uuid,
        ${claim.fencing_token}::bigint,
        ${sqlLiteral(failureClass)}, ${sqlLiteral(code)}, ${sqlLiteral(message)}
      );
    `)
    summary.failed += 1
  }

  return summary
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  if (process.argv[2] !== 'once' || process.argv.length > 4) {
    process.stderr.write('Uso: node scripts/w3d-local-runner.mjs once [batch-size]\n')
    process.exit(1)
  }
  const batchSize = process.argv[3] === undefined ? 10 : Number(process.argv[3])
  process.stdout.write(`${JSON.stringify(await processOnce({ batchSize }))}\n`)
}
