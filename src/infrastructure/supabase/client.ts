import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '@/infrastructure/supabase/database.types'

export type AppSupabaseClient = SupabaseClient<Database>

export interface SupabaseBrowserConfig {
  supabaseUrl: string
  supabaseAnonKey: string
}

export function createAppSupabaseClient(
  config: SupabaseBrowserConfig,
): AppSupabaseClient {
  return createClient<Database>(config.supabaseUrl, config.supabaseAnonKey, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
    },
  })
}
