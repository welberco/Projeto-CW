import { readFile } from 'node:fs/promises'
import { PGlite } from '@electric-sql/pglite'

const projectMigrations = [
  'supabase/migrations/20260910000000_w1a_identity_tenant_core.sql',
  'supabase/migrations/20260910001000_w1a_membership_invitation_entitlement_audit.sql',
  'supabase/migrations/20260910002000_w1a_rls_helpers_and_policies.sql',
  'supabase/migrations/20260910004000_w1c_tenant_context_resolver.sql',
]

const database = new PGlite()

try {
  await database.exec(`
    create role anon;
    create role authenticated;
    create role service_role;
    create schema auth;
    create table auth.users (id uuid primary key);
    create function auth.uid()
    returns uuid
    language sql
    stable
    as 'select null::uuid';
  `)

  for (const migrationPath of projectMigrations) {
    await database.exec(await readFile(migrationPath, 'utf8'))
  }

  const resolver = await database.query(`
    select routine_name
    from information_schema.routines
    where routine_schema = 'public'
      and routine_name = 'resolve_my_tenant_context'
  `)

  if (resolver.rows.length !== 1) {
    throw new Error('W1C resolver was not created by the migration chain.')
  }

  process.stdout.write(
    'PGLITE_W1C_MIGRATION_OK: verificação estrutural auxiliar aprovada; não substitui Supabase/RLS real.\n',
  )
} finally {
  await database.close()
}
