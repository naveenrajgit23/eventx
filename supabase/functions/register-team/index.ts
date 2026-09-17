import { corsHeaders, json } from '../_shared/cors.ts'
import { admin, issueSession, recordParticipantSession } from '../_shared/session.ts'

Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)

  let userId: string | undefined
  let teamId: string | undefined
  try {
    const { team_name, phone_number, event_code } = await req.json()
    if (!team_name || !phone_number || !event_code) {
      return json({ error: 'All fields are required.' }, 400)
    }

    const client = admin()

    const { data: team, error: teamError } = await client.rpc('create_participant_team', {
      p_team_name: String(team_name),
      p_phone_number: String(phone_number),
      p_event_code: String(event_code),
    })
    if (teamError) throw teamError
    teamId = team.team_id

    const { data: event } = await client
      .from('events')
      .select('event_name')
      .eq('id', team.event_id)
      .maybeSingle()

    const email = `team-${crypto.randomUUID()}@participants.eventx.invalid`
    const password = crypto.randomUUID() + crypto.randomUUID()
    const { data: created, error: createError } = await client.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { name: team.team_name, role: 'participant', team_id: team.team_id, event_id: team.event_id },
    })
    if (createError || !created.user) throw createError ?? new Error('user_create_failed')
    userId = created.user.id

    const { error: linkError } = await client.from('teams').update({ user_id: userId }).eq('id', team.team_id)
    if (linkError) throw linkError

    const session = await issueSession(email)
    await recordParticipantSession(team.team_id, session.refresh_token)

    return json(
      {
        team: {
          id: team.team_id,
          team_name: team.team_name,
          team_code: team.team_code,
          event_name: event?.event_name ?? '',
        },
        ...session,
      },
      201
    )
  } catch (error) {
    console.error(error)
    if (userId) await admin().auth.admin.deleteUser(userId)
    if (teamId && !userId) await admin().from('teams').delete().eq('id', teamId)

    // Errors from supabase.rpc()/postgrest are plain {message,details,code}
    // objects, not Error instances — read .message off either shape.
    const rawMessage =
      (error && typeof error === 'object' && 'message' in error ? String((error as { message: unknown }).message) : String(error)) ?? ''

    const message = /team name is required/i.test(rawMessage)
      ? 'Team name is required.'
      : /invalid event code or registration is closed/i.test(rawMessage)
      ? 'Event code not found or registration is closed.'
      : /team name already registered/i.test(rawMessage)
      ? 'That team name is already registered for this event.'
      : /teams_team_code_key/i.test(rawMessage)
      ? 'Could not generate a unique team code — please try again.'
      : /duplicate/i.test(rawMessage)
      ? 'That team is already registered.'
      : 'Team registration could not be completed.'
    return json({ error: message }, 400)
  }
})
