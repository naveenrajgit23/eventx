import { corsHeaders, json } from '../_shared/cors.ts'
import { admin, issueSession, recordParticipantSession } from '../_shared/session.ts'

Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)

  try {
    const { team_name, team_code } = await req.json()
    if (!team_name || !team_code) {
      return json({ error: 'Team name and Team ID are required.' }, 400)
    }

    const client = admin()
    const { data: userId, error } = await client.rpc('verify_participant_login', {
      p_team_name: String(team_name),
      p_team_code: String(team_code),
    })
    if (error || !userId) return json({ error: 'Team name or Team ID is incorrect.' }, 401)

    const { data: userResult, error: userError } = await client.auth.admin.getUserById(userId)
    if (userError || !userResult.user?.email) throw userError ?? new Error('user_not_found')

    const { data: team, error: teamError } = await client
      .from('teams')
      .select('id,team_name,team_code')
      .eq('user_id', userId)
      .single()
    if (teamError || !team) throw teamError ?? new Error('team_not_found')

    const session = await issueSession(userResult.user.email)
    await recordParticipantSession(team.id, session.refresh_token)

    return json({ team, ...session })
  } catch (error) {
    console.error(error)
    return json({ error: 'Login could not be completed.' }, 400)
  }
})
