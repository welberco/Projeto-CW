import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import type { PublicConfig } from '@/app/config/public-config'
import type { Database } from '@/infrastructure/supabase/database.types'

export type AppSupabaseClient = SupabaseClient<Database>

export function createAppSupabaseClient(
  config: Pick<PublicConfig, 'supabaseUrl' | 'supabaseAnonKey'>,
): AppSupabaseClient {
  return createClient<Database>(config.supabaseUrl, config.supabaseAnonKey, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
    },
  })
}
