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
    const message =
      error instanceof Error && error.message.includes('event_code_not_found')
        ? 'Event code not found.'
        : error instanceof Error && error.message.includes('team_name_already_registered')
        ? 'That team name is already registered for this event.'
        : error instanceof Error && error.message.includes('invalid_team_name')
        ? 'Team name must be between 2 and 120 characters.'
        : error instanceof Error && error.message.includes('invalid_phone')
        ? 'Phone number must be between 7 and 20 characters.'
        : error instanceof Error && error.message.toLowerCase().includes('duplicate')
        ? 'That team is already registered.'
        : 'Team registration could not be completed.'
    return json({ error: message }, 400)
  }
})
