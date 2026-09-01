import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined
const demoMode = import.meta.env.DEV && import.meta.env.VITE_DEMO_MODE === "true"

export const isSupabaseConfigured = Boolean(url && key) && !demoMode
export const supabase = isSupabaseConfigured ? createClient(url!, key!) : null
