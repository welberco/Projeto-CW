import { randomUUID } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { spawn, spawnSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const config = readFileSync(path.join(projectRoot, 'supabase', 'config.toml'), 'utf8')
const projectId = /^project_id\s*=\s*"([a-z0-9-]+)"\s*$/mu.exec(config)?.[1]
if (projectId === undefined) throw new Error('W3D_CONCURRENCY_BLOCKER: projeto local ausente.')

const containerName = `supabase_db_${projectId}`
const suffix = randomUUID().replaceAll('-', '')
const actorId = randomUUID()
const tenantId = randomUUID()
const tenantRef = randomUUID()

function psqlArgs(sql) {
  return [
    'exec', '-i', containerName, 'psql', '-X', '-q', '-A', '-t',
    '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres', '-c', sql,
  ]
}

function run(sql, allowFailure = false) {
  const result = spawnSync('docker', psqlArgs(sql), {
    cwd: projectRoot,
    encoding: 'utf8',
    stdio: 'pipe',
  })
  if (!allowFailure && (result.error !== undefined || result.status !== 0)) {
    throw new Error(result.error?.message ?? result.stderr.trim())
  }
  return result
}

function runAsync(sql) {
  return new Promise((resolve, reject) => {
    const child = spawn('docker', psqlArgs(sql), {
      cwd: projectRoot,
      stdio: ['ignore', 'pipe', 'pipe'],
    })
    let stdout = ''
    let stderr = ''
    child.stdout.setEncoding('utf8')
    child.stderr.setEncoding('utf8')
    child.stdout.on('data', (chunk) => { stdout += chunk })
    child.stderr.on('data', (chunk) => { stderr += chunk })
    child.on('error', reject)
    child.on('close', (code) => {
      if (code === 0) resolve(stdout.trim())
      else reject(new Error(stderr.trim() || `psql exited with ${code}`))
    })
  })
}

function parseClaim(output) {
  const line = output.split(/\r?\n/u).find((candidate) =>
    /^[0-9a-f-]{36}\|[0-9a-f-]{36}\|[1-9][0-9]*$/iu.test(candidate.trim()),
  )
  if (line === undefined) throw new Error(`claim output ausente: ${output}`)
  const [eventId, leaseToken, fenceText] = line.trim().split('|')
  return { eventId, leaseToken, fence: Number(fenceText) }
}

function cleanup() {
  run(`
    set session_replication_role = replica;
    delete from private.event_handler_receipts where tenant_id = '${tenantId}';
    delete from private.command_idempotency where tenant_id = '${tenantId}';
    delete from private.outbox_events where tenant_id = '${tenantId}';
    delete from public.history_entries where tenant_id = '${tenantId}';
    delete from public.audit_events where tenant_id = '${tenantId}';
    delete from public.tenant_permission_overrides where tenant_id = '${tenantId}';
    delete from public.tenant_profile_permissions where tenant_id = '${tenantId}';
    delete from public.tenant_memberships where tenant_id = '${tenantId}';
    delete from public.tenant_profiles where tenant_id = '${tenantId}';
    delete from public.tenant_entitlements where tenant_id = '${tenantId}';
    delete from public.tenants where id = '${tenantId}';
    delete from public.app_users where id = '${actorId}';
    delete from auth.users where id = '${actorId}';
    set session_replication_role = origin;
  `, true)
}

try {
  const running = run(`select 1;`)
  if (running.status !== 0) throw new Error('PostgreSQL local indisponível.')

  run(`
    insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
    values ('${actorId}', 'authenticated', 'authenticated',
      'w3d-concurrency-${suffix}@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp());
    insert into public.tenants (id, tenant_ref, display_name, status, created_by)
    values ('${tenantId}', '${tenantRef}', 'W3D Concurrency ${suffix}', 'active', '${actorId}');
    select * from private.provision_tenant_authorization('${tenantId}', null, '${actorId}', '${randomUUID()}');
    insert into public.tenant_memberships (
      tenant_id, user_id, status, joined_at, created_by,
      profile_id, profile_assigned_at, profile_assigned_by
    )
    select '${tenantId}', '${actorId}', 'active', statement_timestamp(), '${actorId}',
      profile.id, statement_timestamp(), '${actorId}'
    from public.tenant_profiles as profile
    where profile.tenant_id = '${tenantId}' and profile.template_key = 'manager';
    begin;
    set local "request.jwt.claim.sub" = '${actorId}';
    set local role authenticated;
    select * from public.create_tenant_profile(
      'W3D Concurrent A ${suffix}', 'create concurrent fixture', '${randomUUID()}', 'w3d-concurrent-a-${suffix}'
    );
    select * from public.create_tenant_profile(
      'W3D Concurrent B ${suffix}', 'create concurrent fixture', '${randomUUID()}', 'w3d-concurrent-b-${suffix}'
    );
    commit;
  `)

  const claimSql = (worker, hold) => `
    begin;
    set local role cw_worker;
    select event_id::text || '|' || lease_token::text || '|' || fencing_token::text
    from public.claim_outbox_batch('${worker}', 1);
    ${hold ? 'select pg_catalog.pg_sleep(1);' : ''}
    commit;
  `

  const firstPromise = runAsync(claimSql('local:w3d-concurrent-a', true))
  await new Promise((resolve) => setTimeout(resolve, 100))
  const secondPromise = runAsync(claimSql('local:w3d-concurrent-b', false))
  const [firstOutput, secondOutput] = await Promise.all([firstPromise, secondPromise])
  const first = parseClaim(firstOutput)
  const second = parseClaim(secondOutput)

  if (first.eventId === second.eventId) {
    throw new Error('workers concorrentes receberam o mesmo evento')
  }

  const noSteal = run(`
    set role cw_worker;
    select count(*) from public.claim_outbox_batch('local:w3d-concurrent-c', 10);
  `).stdout.trim()
  if (noSteal !== '0') throw new Error(`lease válida foi roubada (${noSteal})`)

  run(`
    update private.outbox_events
    set lease_expires_at = statement_timestamp() - interval '1 second'
    where event_id = '${first.eventId}';
  `)
  const reclaimed = parseClaim(run(`
    set role cw_worker;
    select event_id::text || '|' || lease_token::text || '|' || fencing_token::text
    from public.claim_outbox_batch('local:w3d-concurrent-c', 1);
  `).stdout.trim())
  if (reclaimed.eventId !== first.eventId || reclaimed.fence <= first.fence) {
    throw new Error('reclaim não preservou identidade ou não avançou fence')
  }

  for (const action of ['complete', 'fail']) {
    const sql = action === 'complete'
      ? `select * from public.complete_outbox_event('${first.eventId}','local:w3d-concurrent-a','${first.leaseToken}',${first.fence},1,'{}');`
      : `select * from public.fail_outbox_event('${first.eventId}','local:w3d-concurrent-a','${first.leaseToken}',${first.fence},'retryable','STALE_WORKER','Stale worker failure.');`
    const stale = run(`set role cw_worker; ${sql}`, true)
    if (stale.status === 0 || !stale.stderr.includes('OUTBOX_LEASE_STALE')) {
      throw new Error(`worker stale conseguiu executar ${action}`)
    }
  }

  run(`
    select * from private.record_event_handler_receipt(
      'cw.authorization.profile_projection', '${reclaimed.eventId}',
      'authorization_profile_created_v1', 1, 1, '{"effect":"already-committed"}'
    );
  `)
  const completed = run(`
    set role cw_worker;
    select receipt_replayed
    from public.complete_outbox_event(
      '${reclaimed.eventId}', 'local:w3d-concurrent-c',
      '${reclaimed.leaseToken}', ${reclaimed.fence}, 1, '{"effect":"must-not-repeat"}'
    );
  `).stdout.trim()
  if (completed !== 't') throw new Error('ack não reconheceu receipt já persistido')

  const finalState = run(`
    select
      (select count(*) from private.outbox_events where tenant_id = '${tenantId}' and status = 'processed'),
      (select count(*) from private.event_handler_receipts where tenant_id = '${tenantId}' and event_id = '${reclaimed.eventId}'),
      (select count(*) from private.outbox_events where tenant_id = '${tenantId}' and status = 'processing');
  `).stdout.trim()
  if (finalState !== '1|1|1') throw new Error(`estado concorrente inesperado (${finalState})`)

  process.stdout.write(
    'W3D_CONCURRENCY_OK: disjoint SKIP LOCKED claims, valid lease protection, expired reclaim, monotonic fence, stale ack/fail rejection and receipt replay verified.\n',
  )
} finally {
  cleanup()
}
