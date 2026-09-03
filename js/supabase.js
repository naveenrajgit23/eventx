import { createClient } from '@supabase/supabase-js'
const url=import.meta.env.VITE_SUPABASE_URL
const key=import.meta.env.VITE_SUPABASE_ANON_KEY
export const isConfigured=Boolean(url&&key&&!url.includes('your-project'))
export const supabase=isConfigured?createClient(url,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}}):null
export function requireConfiguration(){if(!isConfigured)throw new Error('SETUP_REQUIRED')}
export function friendlyError(error){console.error(error);const messages={SETUP_REQUIRED:'Connect Supabase to use this feature. See the setup guide.',invalid_credentials:'Those login details are not correct.',round_locked:'This round is already locked.',not_authorized:'You are not authorized to perform this action.'};return messages[error?.message]||messages[error?.code]||'Something went wrong. Please try again.'}
