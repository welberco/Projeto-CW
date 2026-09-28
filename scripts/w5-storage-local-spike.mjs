import { createHash, randomUUID } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createClient } from '@supabase/supabase-js'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const configPath = path.join(root, 'supabase', 'config.toml')
const config = readFileSync(configPath, 'utf8')
const projectId = /^project_id\s*=\s*"([a-z0-9-]+)"\s*$/mu.exec(config)?.[1]
const expectedProjectId = 'cw-erp-v2-local'
const bucket = 'cw-private-files'
const bucketLimit = 1024 * 1024
const allowedMimeTypes = ['image/png', 'image/jpeg', 'application/pdf']
const storageContainer = `supabase_storage_${expectedProjectId}`
const databaseContainer = `supabase_db_${expectedProjectId}`
const cli = path.join(root, 'node_modules', 'supabase', 'dist', 'supabase.js')
const emails = Object.freeze({
  allowedA: 'w5-storage-spike-allowed-a@example.invalid',
  deniedA: 'w5-storage-spike-denied-a@example.invalid',
  allowedB: 'w5-storage-spike-allowed-b@example.invalid',
})
const scenarioNames = [
  'storage_health',
  'bucket_private',
  'public_access_denied',
  'signed_upload_allowed',
  'signed_upload_denied',
  'cross_tenant_reservation_denied',
  'forged_key_denied',
  'exact_signed_upload',
  'token_other_key_denied',
  'overwrite_denied',
  'upload_without_session',
  'token_after_permission_loss_observed',
  'finalize_after_revocation_denied',
  'private_object_not_public',
  'signed_read_authorized',
  'signed_read_expired',
  'object_info_available',
  'observed_size_exact',
  'mime_dimensions_separated',
  'spoof_mime_detected',
  'png_sniff',
  'jpeg_sniff',
  'pdf_sniff',
  'sha256_deterministic',
  'sha256_one_byte_change',
  'bucket_limit_enforced',
  'normal_user_delete_denied',
  'technical_inspect_download',
  'technical_delete',
  'delete_removes_object',
  'idempotent_delete_adapter',
  'read_info_after_delete_denied',
  'cleanup_finalize_fence',
  'no_capability_persisted',
  'no_capability_in_audit_outbox',
  'harness_logs_secret_free',
  'storage_logs_secret_free',
  'teardown',
  'repeatable_after_teardown',
]
const results = new Map(scenarioNames.map((name) => [name, 'NOT_RUN']))
const failures = []
const observations = new Map([
  ['signed_upload_ttl_documented', '2h'],
  ['technical_authority_observed', 'INCONCLUSIVE'],
  ['service_role_required', 'INCONCLUSIVE'],
])
const secrets = new Set()
const objectKeys = new Set()
let apiUrl
let anonKey
let serviceRoleKey
let serviceClient
let setupStarted = false
let bucketCreatedByRun = false

const png = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  'base64',
)
const jpeg = Buffer.from(
  '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAEf/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQJ//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAwEBPwF//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPwF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwJ//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPyF//9oADAMBAAIAAwAAABAf/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAwEBPxB//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPxB//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxB//9k=',
  'base64',
)
const pdf = Buffer.from(
  '%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Count 0 /Kids [] >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n',
  'ascii',
)
const spoof = Buffer.from('not-an-image-w5-storage-spike', 'utf8')
const oversized = Buffer.alloc(bucketLimit + 1, 0x57)

function mark(name, passed, detail) {
  results.set(name, passed ? 'PASS' : 'FAIL')
  if (!passed) failures.push({ name, category: 'assertion', message: detail ?? 'assertion failed' })
}

function recordFailure(name, category, error) {
  if (results.has(name)) results.set(name, 'FAIL')
  failures.push({ name, category, message: sanitize(error instanceof Error ? error.message : String(error)) })
}

function sanitize(value) {
  let sanitized = String(value ?? '')
  for (const secret of secrets) {
    if (secret.length > 0) sanitized = sanitized.replaceAll(secret, '[REDACTED]')
  }
  return sanitized
    .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/gu, '[REDACTED_JWT]')
    .replace(/([?&](?:token|signature)=)[^&\s]+/giu, '$1[REDACTED]')
    .replace(/\b(?:service_role|anon)_key\s*[=:]\s*\S+/giu, '[REDACTED_KEY]')
    .slice(0, 500)
}

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: root,
    env: {
      ...process.env,
      DO_NOT_TRACK: '1',
      SUPABASE_TELEMETRY_DISABLED: '1',
    },
    encoding: 'utf8',
    input: options.input,
    maxBuffer: 20 * 1024 * 1024,
    stdio: 'pipe',
  })
  if (result.error !== undefined || result.status !== 0) {
    throw new Error(result.error?.message ?? result.stderr?.trim() ?? `${command} exited ${result.status}`)
  }
  return result.stdout ?? ''
}

function sql(statement) {
  return run(
    'docker',
    ['exec', '-i', databaseContainer, 'psql', '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'],
    { input: statement },
  ).trim()
}

function guardLocalOnly() {
  assert(projectId === expectedProjectId, 'REMOTE_GUARD: unexpected local project_id')
  assert(/^\[storage\][\s\S]*?^enabled\s*=\s*true\s*$/mu.test(config), 'Storage is not enabled locally')
  assert(/^file_size_limit\s*=\s*"50MiB"\s*$/mu.test(config), 'Global Storage ceiling is not 50MiB')
  for (const variable of ['SUPABASE_ACCESS_TOKEN', 'SUPABASE_PROJECT_REF', 'SUPABASE_DB_URL']) {
    assert(!process.env[variable], `REMOTE_GUARD: ${variable} must be absent`)
  }
  for (const variable of ['SUPABASE_URL', 'NEXT_PUBLIC_SUPABASE_URL', 'VITE_SUPABASE_URL']) {
    const value = process.env[variable]
    if (!value) continue
    const target = new URL(value)
    assert(['127.0.0.1', 'localhost'].includes(target.hostname), `REMOTE_GUARD: ${variable} is not loopback`)
  }
}

function loadLocalStatus() {
  const output = run(process.execPath, [cli, 'status', '--output', 'env'])
  const values = new Map()
  for (const line of output.split(/\r?\n/u)) {
    const match = /^([A-Z][A-Z0-9_]*)=(?:"([^"]*)"|'([^']*)'|(.*))$/u.exec(line.trim())
    if (match) values.set(match[1], match[2] ?? match[3] ?? match[4] ?? '')
  }
  apiUrl = values.get('API_URL')
  anonKey = values.get('ANON_KEY') ?? values.get('PUBLISHABLE_KEY')
  serviceRoleKey = values.get('SERVICE_ROLE_KEY') ?? values.get('SECRET_KEY')
  assert(apiUrl && anonKey && serviceRoleKey, 'Local Supabase status omitted required runtime values')
  const parsed = new URL(apiUrl)
  assert(['127.0.0.1', 'localhost'].includes(parsed.hostname), 'REMOTE_GUARD: API URL is not loopback')
  assert(parsed.protocol === 'http:', 'REMOTE_GUARD: local API URL must use http')
  secrets.add(anonKey)
  secrets.add(serviceRoleKey)
  serviceClient = createClient(apiUrl, serviceRoleKey, clientOptions())
}

function clientOptions() {
  return { auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false } }
}

async function removeReservedUsers() {
  if (!serviceClient) return
  const reservedEmails = new Set(Object.values(emails))
  const reservedUsers = []
  let page = 1
  while (page <= 10) {
    const { data, error } = await serviceClient.auth.admin.listUsers({ page, perPage: 100 })
    if (error) throw error
    for (const user of data.users) {
      if (reservedEmails.has(user.email ?? '')) reservedUsers.push(user)
    }
    if (data.users.length < 100) break
    page += 1
  }

  for (const user of reservedUsers) {
    assert(/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/iu.test(user.id), 'Auth Admin returned an invalid reserved user UUID')
    sql(`delete from public.app_users where id = '${user.id}'::uuid;`)
    const deleted = await serviceClient.auth.admin.deleteUser(user.id)
    if (deleted.error) throw deleted.error
  }
}

async function removeExactBucket() {
  if (!serviceClient) return
  const bucketResult = await serviceClient.storage.getBucket(bucket)
  if (bucketResult.error) return
  const markerPresent = sql(`select to_regclass('public.w5_storage_spike_reservations') is not null;`) === 't'
  assert(bucketCreatedByRun || markerPresent, 'Exact bucket exists without the W5 spike ownership marker')
  const emptied = await serviceClient.storage.emptyBucket(bucket)
  if (emptied.error) throw emptied.error
  const deleted = await serviceClient.storage.deleteBucket(bucket)
  if (deleted.error) throw deleted.error
}

function dropSpikeSql() {
  sql(`
drop policy if exists w5_storage_spike_insert on storage.objects;
drop policy if exists w5_storage_spike_select on storage.objects;
drop function if exists public.w5_storage_spike_finalize_probe(text);
drop function if exists public.w5_storage_spike_claim_cleanup(text);
drop function if exists private.w5_storage_spike_can_insert(text,text);
drop function if exists private.w5_storage_spike_can_read(text,text);
drop table if exists public.w5_storage_spike_reservations;
drop table if exists public.w5_storage_spike_principals;
`)
}

async function reconcile() {
  await removeExactBucket()
  dropSpikeSql()
  await removeReservedUsers()
}

function installSpikeSql() {
  sql(`
create table public.w5_storage_spike_reservations (
  object_key text primary key,
  tenant_id uuid not null,
  user_id uuid not null,
  capability_allowed boolean not null default false,
  available boolean not null default false,
  cleanup_claimed boolean not null default false,
  declared_mime text not null,
  verified_mime text,
  observed_size bigint,
  observed_sha256 text,
  created_at timestamptz not null default statement_timestamp(),
  constraint w5_storage_spike_key_ck check (object_key ~ '^v1/[0-9a-f-]{36}$')
);
create table public.w5_storage_spike_principals (
  user_id uuid primary key,
  tenant_id uuid not null
);
alter table public.w5_storage_spike_reservations enable row level security;
alter table public.w5_storage_spike_principals enable row level security;
revoke all on table public.w5_storage_spike_reservations from public, anon, authenticated;
revoke all on table public.w5_storage_spike_principals from public, anon, authenticated;

create function private.w5_storage_spike_can_insert(target_bucket text, target_key text)
returns boolean language sql stable security definer set search_path = '' as $$
  select target_bucket = 'cw-private-files'
     and exists (
       select 1
       from public.w5_storage_spike_reservations reservation
       join public.w5_storage_spike_principals principal
         on principal.user_id = reservation.user_id
        and principal.tenant_id = reservation.tenant_id
       where reservation.object_key = target_key
         and principal.user_id = auth.uid()
         and reservation.capability_allowed
         and not reservation.available
         and not reservation.cleanup_claimed
     );
$$;
revoke all on function private.w5_storage_spike_can_insert(text,text) from public;
grant execute on function private.w5_storage_spike_can_insert(text,text) to authenticated;

create function private.w5_storage_spike_can_read(target_bucket text, target_key text)
returns boolean language sql stable security definer set search_path = '' as $$
  select target_bucket = 'cw-private-files'
     and exists (
       select 1
       from public.w5_storage_spike_reservations reservation
       join public.w5_storage_spike_principals principal
         on principal.user_id = reservation.user_id
        and principal.tenant_id = reservation.tenant_id
       where reservation.object_key = target_key
         and principal.user_id = auth.uid()
         and reservation.capability_allowed
         and reservation.available
         and not reservation.cleanup_claimed
     );
$$;
revoke all on function private.w5_storage_spike_can_read(text,text) from public;
grant execute on function private.w5_storage_spike_can_read(text,text) to authenticated;

create policy w5_storage_spike_insert on storage.objects
for insert to authenticated
with check ((select private.w5_storage_spike_can_insert(bucket_id,name)));

create policy w5_storage_spike_select on storage.objects
for select to authenticated
using ((select private.w5_storage_spike_can_read(bucket_id,name)));

create function public.w5_storage_spike_finalize_probe(target_key text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare reservation public.w5_storage_spike_reservations%rowtype;
begin
  select * into reservation
  from public.w5_storage_spike_reservations candidate
  where candidate.object_key = target_key
  for update;
  if not found
     or reservation.user_id is distinct from auth.uid()
     or not reservation.capability_allowed
     or reservation.cleanup_claimed
     or not exists (
       select 1 from storage.objects object
       where object.bucket_id = 'cw-private-files' and object.name = target_key
     ) then
    return false;
  end if;
  update public.w5_storage_spike_reservations set available = true where object_key = target_key;
  return true;
end;
$$;
revoke all on function public.w5_storage_spike_finalize_probe(text) from public;
grant execute on function public.w5_storage_spike_finalize_probe(text) to authenticated;

create function public.w5_storage_spike_claim_cleanup(target_key text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare claimed boolean := false;
begin
  update public.w5_storage_spike_reservations
  set cleanup_claimed = true
  where object_key = target_key and not available and not cleanup_claimed
  returning true into claimed;
  return coalesce(claimed,false);
end;
$$;
revoke all on function public.w5_storage_spike_claim_cleanup(text) from public, anon, authenticated;
grant execute on function public.w5_storage_spike_claim_cleanup(text) to service_role;
`)
}

async function createSyntheticUser(email) {
  const password = `W5-${randomUUID()}-Local!`
  secrets.add(password)
  const created = await serviceClient.auth.admin.createUser({ email, password, email_confirm: true })
  if (created.error || !created.data.user) throw created.error ?? new Error('Synthetic user was not created')
  const client = createClient(apiUrl, anonKey, clientOptions())
  const signedIn = await client.auth.signInWithPassword({ email, password })
  if (signedIn.error || !signedIn.data.session) throw signedIn.error ?? new Error('Synthetic user sign-in failed')
  secrets.add(signedIn.data.session.access_token)
  secrets.add(signedIn.data.session.refresh_token)
  return { id: created.data.user.id, client }
}

function reserve(key, user, tenant, declaredMime, allowed = true) {
  objectKeys.add(key)
  sql(`insert into public.w5_storage_spike_reservations(object_key,tenant_id,user_id,capability_allowed,declared_mime)
       values ('${key}','${tenant}','${user}',${allowed ? 'true' : 'false'},'${declaredMime}');`)
}

function registerPrincipal(user, tenant) {
  sql(`insert into public.w5_storage_spike_principals(user_id,tenant_id) values ('${user}','${tenant}');`)
}

function setAllowed(key, allowed) {
  sql(`update public.w5_storage_spike_reservations set capability_allowed=${allowed ? 'true' : 'false'} where object_key='${key}';`)
}

async function signedCapability(client, key) {
  const result = await client.storage.from(bucket).createSignedUploadUrl(key, { upsert: false })
  if (result.data?.token) secrets.add(result.data.token)
  if (result.data?.signedUrl) secrets.add(result.data.signedUrl)
  return result
}

async function signedUpload(key, token, bytes, contentType) {
  return createClient(apiUrl, anonKey, clientOptions()).storage
    .from(bucket)
    .uploadToSignedUrl(key, token, bytes, { contentType, upsert: false })
}

function sniff(bytes) {
  if (bytes.length >= 8 && bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png'
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return 'image/jpeg'
  if (bytes.length >= 5 && bytes.subarray(0, 5).equals(Buffer.from('%PDF-', 'ascii'))) return 'application/pdf'
  return null
}

function sha256(bytes) {
  const hash = createHash('sha256')
  const chunkSize = 64 * 1024
  for (let offset = 0; offset < bytes.length; offset += chunkSize) hash.update(bytes.subarray(offset, offset + chunkSize))
  return hash.digest('hex')
}

async function downloadBuffer(client, key) {
  const result = await client.storage.from(bucket).download(key)
  if (result.error || !result.data) throw result.error ?? new Error('Object download returned no data')
  return Buffer.from(await result.data.arrayBuffer())
}

async function removeIdempotently(key) {
  const info = await serviceClient.storage.from(bucket).info(key)
  if (info.error) return 'ALREADY_ABSENT'
  const removed = await serviceClient.storage.from(bucket).remove([key])
  if (removed.error) throw removed.error
  return 'REMOVED'
}

async function callFinalize(client, key) {
  const result = await client.rpc('w5_storage_spike_finalize_probe', { target_key: key })
  if (result.error) throw result.error
  return result.data === true
}

async function runScenarios() {
  const health = await fetch(`${apiUrl}/storage/v1/status`)
  mark('storage_health', health.ok, `Storage health returned ${health.status}`)

  installSpikeSql()
  const createdBucket = await serviceClient.storage.createBucket(bucket, {
    public: false,
    fileSizeLimit: bucketLimit,
    allowedMimeTypes,
  })
  assert(!createdBucket.error, createdBucket.error?.message)
  bucketCreatedByRun = true
  const bucketState = await serviceClient.storage.getBucket(bucket)
  mark('bucket_private', !bucketState.error && bucketState.data?.public === false, 'Bucket was not private')

  const [allowedA, deniedA, allowedB] = await Promise.all([
    createSyntheticUser(emails.allowedA),
    createSyntheticUser(emails.deniedA),
    createSyntheticUser(emails.allowedB),
  ])
  const tenantA = randomUUID()
  const tenantB = randomUUID()
  const mainKey = `v1/${randomUUID()}`
  const revokedKey = `v1/${randomUUID()}`
  const deniedKey = `v1/${randomUUID()}`
  const pngKey = `v1/${randomUUID()}`
  const jpegKey = `v1/${randomUUID()}`
  const pdfKey = `v1/${randomUUID()}`
  const spoofKey = `v1/${randomUUID()}`
  const oversizedKey = `v1/${randomUUID()}`
  registerPrincipal(allowedA.id, tenantA)
  registerPrincipal(deniedA.id, tenantA)
  registerPrincipal(allowedB.id, tenantB)
  reserve(mainKey, allowedA.id, tenantA, 'image/png')
  reserve(revokedKey, allowedA.id, tenantA, 'image/png')
  reserve(deniedKey, deniedA.id, tenantA, 'image/png', false)
  reserve(pngKey, allowedA.id, tenantA, 'image/png')
  reserve(jpegKey, allowedA.id, tenantA, 'image/jpeg')
  reserve(pdfKey, allowedA.id, tenantA, 'application/pdf')
  reserve(spoofKey, allowedA.id, tenantA, 'image/png')
  reserve(oversizedKey, allowedA.id, tenantA, 'image/png')

  const publicUrl = serviceClient.storage.from(bucket).getPublicUrl(mainKey).data.publicUrl
  const publicResponse = await fetch(publicUrl)
  mark('public_access_denied', !publicResponse.ok, `Private pre-upload URL returned ${publicResponse.status}`)

  const mainCapability = await signedCapability(allowedA.client, mainKey)
  mark('signed_upload_allowed', !mainCapability.error && Boolean(mainCapability.data?.token), mainCapability.error?.message)
  const deniedCapability = await signedCapability(deniedA.client, deniedKey)
  mark('signed_upload_denied', Boolean(deniedCapability.error), 'Denied principal received an upload capability')
  const crossTenant = await signedCapability(allowedB.client, mainKey)
  mark('cross_tenant_reservation_denied', Boolean(crossTenant.error), 'Tenant B principal used Tenant A reservation')
  const forged = await signedCapability(allowedA.client, `v1/${randomUUID()}`)
  mark('forged_key_denied', Boolean(forged.error), 'Unreserved key received an upload capability')

  if (!mainCapability.data) throw new Error('Main capability unavailable')
  const wrongKeyUpload = await signedUpload(`v1/${randomUUID()}`, mainCapability.data.token, png, 'image/png')
  mark('token_other_key_denied', Boolean(wrongKeyUpload.error), 'Capability accepted another key')
  const uploaded = await signedUpload(mainKey, mainCapability.data.token, png, 'image/png')
  mark('exact_signed_upload', !uploaded.error, uploaded.error?.message)
  mark('upload_without_session', !uploaded.error, 'Anonymous token upload failed')
  const overwritten = await signedUpload(mainKey, mainCapability.data.token, png, 'image/png')
  mark('overwrite_denied', Boolean(overwritten.error), 'upsert=false capability overwrote existing object')

  const revokedCapability = await signedCapability(allowedA.client, revokedKey)
  assert(revokedCapability.data?.token, revokedCapability.error?.message ?? 'Revocation capability unavailable')
  setAllowed(revokedKey, false)
  const postRevocationUpload = await signedUpload(revokedKey, revokedCapability.data.token, png, 'image/png')
  observations.set('token_after_permission_loss', postRevocationUpload.error ? 'DENIED' : 'ACCEPTED')
  mark('token_after_permission_loss_observed', true)
  const revokedFinalize = await callFinalize(allowedA.client, revokedKey)
  mark('finalize_after_revocation_denied', revokedFinalize === false, 'Finalize accepted revoked permission')

  setAllowed(mainKey, true)
  const finalized = await callFinalize(allowedA.client, mainKey)
  assert(finalized, 'Main object finalize probe failed')
  const privateResponse = await fetch(publicUrl)
  mark('private_object_not_public', !privateResponse.ok, `Private object returned ${privateResponse.status}`)

  const signedRead = await allowedA.client.storage.from(bucket).createSignedUrl(mainKey, 3)
  if (signedRead.data?.signedUrl) secrets.add(signedRead.data.signedUrl)
  const signedReadResponse = signedRead.data?.signedUrl ? await fetch(signedRead.data.signedUrl) : undefined
  mark('signed_read_authorized', !signedRead.error && signedReadResponse?.ok === true, signedRead.error?.message ?? 'Signed read failed')
  await new Promise((resolve) => setTimeout(resolve, 5500))
  const expiredResponse = signedRead.data?.signedUrl ? await fetch(signedRead.data.signedUrl) : undefined
  mark('signed_read_expired', expiredResponse !== undefined && !expiredResponse.ok, `Expired signed read returned ${expiredResponse?.status}`)

  const info = await allowedA.client.storage.from(bucket).info(mainKey)
  mark('object_info_available', !info.error && Boolean(info.data), info.error?.message)
  mark('observed_size_exact', Number(info.data?.size) === png.length, `Observed ${info.data?.size}, expected ${png.length}`)
  const recordedMainMime = info.data?.contentType ?? info.data?.metadata?.mimetype ?? null
  const verifiedMainMime = sniff(png)
  observations.set('declared_mime', 'image/png')
  observations.set('storage_recorded_content_type', recordedMainMime ?? 'null')
  observations.set('verified_mime', verifiedMainMime ?? 'null')
  mark(
    'mime_dimensions_separated',
    recordedMainMime === 'image/png' && verifiedMainMime === 'image/png',
    `Recorded=${recordedMainMime ?? 'null'} verified=${verifiedMainMime ?? 'null'}`,
  )

  const fixtureCases = [
    { key: pngKey, bytes: png, type: 'image/png', scenario: 'png_sniff' },
    { key: jpegKey, bytes: jpeg, type: 'image/jpeg', scenario: 'jpeg_sniff' },
    { key: pdfKey, bytes: pdf, type: 'application/pdf', scenario: 'pdf_sniff' },
    { key: spoofKey, bytes: spoof, type: 'image/png', scenario: 'spoof_mime_detected' },
  ]
  for (const fixture of fixtureCases) {
    const capability = await signedCapability(allowedA.client, fixture.key)
    assert(capability.data?.token, capability.error?.message ?? `${fixture.scenario} capability unavailable`)
    const fixtureUpload = await signedUpload(fixture.key, capability.data.token, fixture.bytes, fixture.type)
    if (fixtureUpload.error) {
      if (fixture.scenario === 'spoof_mime_detected') {
        observations.set('spoof_storage_behavior', 'REJECTED_BEFORE_VERIFICATION')
        mark(fixture.scenario, true)
        continue
      }
      mark(fixture.scenario, false, fixtureUpload.error.message)
      continue
    }
    const observed = await downloadBuffer(serviceClient, fixture.key)
    const verified = sniff(observed)
    if (fixture.scenario === 'spoof_mime_detected') {
      observations.set('spoof_storage_behavior', 'ACCEPTED_PHYSICALLY_VERIFICATION_REJECTED')
      mark(fixture.scenario, verified === null, `Spoof verified unexpectedly as ${verified}`)
    } else {
      mark(fixture.scenario, verified === fixture.type, `Sniff returned ${verified ?? 'null'}`)
    }
  }

  const technicalBytes = await downloadBuffer(serviceClient, mainKey)
  const digest = sha256(technicalBytes)
  mark('sha256_deterministic', digest === sha256(Buffer.from(technicalBytes)), 'Same bytes changed SHA-256')
  const changed = Buffer.from(technicalBytes)
  changed[changed.length - 1] ^= 0x01
  mark('sha256_one_byte_change', digest !== sha256(changed), 'One-byte change retained SHA-256')

  const oversizedCapability = await signedCapability(allowedA.client, oversizedKey)
  assert(oversizedCapability.data?.token, oversizedCapability.error?.message ?? 'Oversized capability unavailable')
  const oversizedUpload = await signedUpload(oversizedKey, oversizedCapability.data.token, oversized, 'image/png')
  mark('bucket_limit_enforced', Boolean(oversizedUpload.error), 'Bucket accepted 1 MiB + 1 byte')

  const userDelete = await allowedA.client.storage.from(bucket).remove([mainKey])
  const afterUserDelete = await serviceClient.storage.from(bucket).info(mainKey)
  observations.set('normal_user_delete_response', userDelete.error ? 'DENIED' : 'NO_OP')
  mark('normal_user_delete_denied', !afterUserDelete.error, 'Normal user deleted physical object')
  const technicalInfo = await serviceClient.storage.from(bucket).info(mainKey)
  const technicalDownload = await downloadBuffer(serviceClient, mainKey)
  mark(
    'technical_inspect_download',
    !technicalInfo.error && technicalDownload.equals(png),
    technicalInfo.error?.message ?? 'Technical download differed',
  )
  observations.set('technical_authority_observed', 'SERVICE_ROLE_STORAGE_API_AFTER_DB_DECISION')
  observations.set('service_role_required', 'YES')

  const removal = await removeIdempotently(mainKey)
  mark('technical_delete', removal === 'REMOVED', 'Technical adapter did not delete exact object')
  const afterDelete = await serviceClient.storage.from(bucket).info(mainKey)
  mark('delete_removes_object', Boolean(afterDelete.error), 'Deleted object still has info')
  const repeatedRemoval = await removeIdempotently(mainKey)
  mark('idempotent_delete_adapter', repeatedRemoval === 'ALREADY_ABSENT', 'Repeated delete was not normalized')
  const userInfoAfterDelete = await allowedA.client.storage.from(bucket).info(mainKey)
  const userReadAfterDelete = await allowedA.client.storage.from(bucket).download(mainKey)
  mark('read_info_after_delete_denied', Boolean(userInfoAfterDelete.error) && Boolean(userReadAfterDelete.error), 'Deleted object remained readable')

  const raceKey = pngKey
  const raceFinalize = callFinalize(allowedA.client, raceKey)
  const raceCleanup = serviceClient.rpc('w5_storage_spike_claim_cleanup', { target_key: raceKey })
  const [raceFinalized, raceClaim] = await Promise.all([raceFinalize, raceCleanup])
  if (raceClaim.error) throw raceClaim.error
  if (raceClaim.data === true) await removeIdempotently(raceKey)
  const raceAvailable = sql(`select available from public.w5_storage_spike_reservations where object_key='${raceKey}';`)
  const raceObject = await serviceClient.storage.from(bucket).info(raceKey)
  const fenced = raceFinalized
    ? raceClaim.data === false && raceAvailable === 't' && !raceObject.error
    : raceClaim.data === true && raceAvailable === 'f' && Boolean(raceObject.error)
  mark('cleanup_finalize_fence', fenced, 'Finalize and cleanup both won for one object')

  const persistedCapability = sql(`select
    (select count(*) from information_schema.columns
      where table_schema='public' and table_name in ('w5_storage_spike_reservations','w5_storage_spike_principals')
        and column_name in ('token','signed_token','signed_url','url'))
    + (select count(*) from public.w5_storage_spike_reservations reservation
       where row_to_json(reservation)::text ~* '(signed[_ ]?url|https?://|eyJ[A-Za-z0-9_-]+\\.)');`)
  mark('no_capability_persisted', persistedCapability === '0', 'Spike DB contains capability-bearing structure or data')
  const auditTouched = sql(`select
    (select count(*) from public.audit_events where metadata::text like '%w5-storage-spike%')
    + (select count(*) from private.outbox_events where payload::text like '%w5-storage-spike%');`)
  mark('no_capability_in_audit_outbox', auditTouched === '0', 'Spike wrote Audit/Outbox payloads')
  mark('harness_logs_secret_free', true)

  try {
    const storageLogs = run('docker', ['logs', storageContainer])
    const leaked = [...secrets].some((secret) => secret.length >= 16 && storageLogs.includes(secret))
    mark('storage_logs_secret_free', !leaked, 'Local Storage logs contain an issued capability or credential')
  } catch (error) {
    recordFailure('storage_logs_secret_free', 'inspection', error)
  }
}

async function teardown() {
  const errors = []
  try { await removeExactBucket() } catch (error) { errors.push(`bucket: ${sanitize(error.message)}`) }
  try { dropSpikeSql() } catch (error) { errors.push(`sql: ${sanitize(error.message)}`) }
  try { await removeReservedUsers() } catch (error) { errors.push(`users: ${sanitize(error.message)}`) }
  return errors
}

async function verifyRepeatable() {
  const bucketState = await serviceClient.storage.getBucket(bucket)
  const sqlArtifacts = sql(`select
    to_regclass('public.w5_storage_spike_reservations') is not null
    or to_regclass('public.w5_storage_spike_principals') is not null
    or to_regprocedure('public.w5_storage_spike_finalize_probe(text)') is not null
    or to_regprocedure('private.w5_storage_spike_can_insert(text,text)') is not null;`)
  const reservedUsers = Number(sql(`select count(*) from auth.users where email = any(array[${Object.values(emails).map((email) => `'${email}'`).join(',')}]);`))
  return Boolean(bucketState.error) && sqlArtifacts === 'f' && reservedUsers === 0
}

function printResults() {
  const output = ['W5_STORAGE_SPIKE']
  for (const name of scenarioNames) output.push(`${name}=${results.get(name)}`)
  for (const [name, value] of observations) output.push(`${name}=${value}`)
  for (const failure of failures) {
    output.push(`failure_scenario=${failure.name}`)
    output.push(`failure_category=${failure.category}`)
    output.push(`failure_message=${sanitize(failure.message)}`)
  }
  const passed = scenarioNames.every((name) => results.get(name) === 'PASS') && failures.length === 0
  output.push(`result=${passed ? 'PASS' : 'FAIL'}`)
  const rendered = `${output.join('\n')}\n`
  const leaked = [...secrets].some((secret) => secret.length >= 8 && rendered.includes(secret))
  if (leaked) {
    process.stdout.write('W5_STORAGE_SPIKE\nharness_logs_secret_free=FAIL\nresult=FAIL\n')
    process.exitCode = 1
    return
  }
  process.stdout.write(rendered)
  if (!passed) process.exitCode = 1
}

async function main() {
  try {
    guardLocalOnly()
    loadLocalStatus()
    setupStarted = true
    await reconcile()
    await runScenarios()
  } catch (error) {
    recordFailure('storage_health', 'harness', error)
  } finally {
    if (setupStarted) {
      const teardownErrors = await teardown()
      mark('teardown', teardownErrors.length === 0, teardownErrors.join('; '))
      try {
        mark('repeatable_after_teardown', teardownErrors.length === 0 && await verifyRepeatable(), 'Exact spike resources remain after teardown')
      } catch (error) {
        recordFailure('repeatable_after_teardown', 'teardown_verification', error)
      }
    } else {
      mark('teardown', true)
      mark('repeatable_after_teardown', false, 'Local guard/status failed before reconciliation')
    }
    printResults()
  }
}

await main()
