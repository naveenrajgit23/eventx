import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

export const admin = () =>
  createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { autoRefreshToken: false, persistSession: false },
  })

export const anon = () =>
  createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
    auth: { autoRefreshToken: false, persistSession: false },
  })

// Mints a real Supabase session for a user we already control server-side
// (via the service role) without ever needing to know their password —
// used for participants, who authenticate with team name + team code
// rather than a password of their own.
export async function issueSession(email: string) {
  const client = admin()
  const { data: link, error } = await client.auth.admin.generateLink({ type: 'magiclink', email })
  if (error) throw error
  const { data, error: verifyError } = await anon().auth.verifyOtp({
    token_hash: link.properties.hashed_token,
    type: 'magiclink',
  })
  if (verifyError || !data.session) throw verifyError ?? new Error('session_failed')
  return { access_token: data.session.access_token, refresh_token: data.session.refresh_token }
}

export async function hashToken(token: string) {
  const bytes = new TextEncoder().encode(token)
  const digest = await crypto.subtle.digest('SHA-256', bytes)
  return Array.from(new Uint8Array(digest)).map(b => b.toString(16).padStart(2, '0')).join('')
}

export async function recordParticipantSession(teamId: string, refreshToken: string) {
  try {
    await admin().from('participant_sessions').insert({
      team_id: teamId,
      token_hash: await hashToken(refreshToken),
      expires_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
    })
  } catch {
    // Audit trail only — never block a login/registration over it.
  }
}
