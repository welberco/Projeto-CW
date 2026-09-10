import { randomUUID } from 'node:crypto'
import { createClient } from '@supabase/supabase-js'

const requiredNames = [
  'CW_BOOTSTRAP_EMAIL',
  'CW_BOOTSTRAP_PASSWORD',
  'CW_BOOTSTRAP_TENANT_NAME',
  'SUPABASE_URL',
  'SUPABASE_SERVICE_ROLE_KEY',
]

function fail(message) {
  process.stderr.write(`${message}\n`)
  process.exit(1)
}

for (const name of requiredNames) {
  if (typeof process.env[name] !== 'string' || process.env[name].trim() === '') {
    fail(`BOOTSTRAP_CONFIG_MISSING: ${name}`)
  }
}

const supabaseUrl = new URL(process.env.SUPABASE_URL)
if (!['127.0.0.1', 'localhost', '::1'].includes(supabaseUrl.hostname)) {
  fail('LOCAL_BOOTSTRAP_ONLY: o runner W1B aceita somente Supabase local.')
}

const email = process.env.CW_BOOTSTRAP_EMAIL.trim().toLowerCase()
const password = process.env.CW_BOOTSTRAP_PASSWORD
const tenantDisplayName = process.env.CW_BOOTSTRAP_TENANT_NAME.trim()

if (!email.includes('@') || password.length < 12 || tenantDisplayName.length === 0) {
  fail('BOOTSTRAP_CONFIG_INVALID')
}

const client = createClient(
  supabaseUrl.toString(),
  process.env.SUPABASE_SERVICE_ROLE_KEY,
  { auth: { persistSession: false, autoRefreshToken: false } },
)

const { data: identity, error: identityError } = await client.auth.admin.createUser({
  email,
  password,
  email_confirm: true,
})

if (identityError !== null || identity.user === null) {
  fail('BOOTSTRAP_AUTH_IDENTITY_FAILED')
}

const { data: bootstrapResult, error: bootstrapError } = await client.rpc(
  'bootstrap_initial_tenant',
  {
    bootstrap_user_id: identity.user.id,
    tenant_display_name: tenantDisplayName,
    correlation_id: randomUUID(),
  },
)

if (bootstrapError !== null) {
  if (bootstrapError.message.includes('SYSTEM_ALREADY_INITIALIZED')) {
    fail('SYSTEM_ALREADY_INITIALIZED')
  }
  fail('BOOTSTRAP_DATABASE_COMMAND_FAILED')
}

const result = Array.isArray(bootstrapResult) ? bootstrapResult[0] : null
if (result === null || typeof result.tenant_ref !== 'string') {
  fail('BOOTSTRAP_RESULT_INVALID')
}

process.stdout.write(`BOOTSTRAP_OK tenant_ref=${result.tenant_ref}\n`)
