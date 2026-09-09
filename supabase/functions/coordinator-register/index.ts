import { corsHeaders, json } from '../_shared/cors.ts'
import { admin, issueSession } from '../_shared/session.ts'

Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)

  let userId: string | undefined
  try {
    const { username, name, password } = await req.json()
    const cleanUsername = String(username ?? '').trim()
    const cleanName = String(name ?? '').trim()

    if (!/^[A-Za-z0-9_]{3,30}$/.test(cleanUsername)) {
      return json({ error: 'Username must be 3–30 letters, numbers, or underscores.' }, 400)
    }
    if (cleanName.length < 2) {
      return json({ error: 'Please enter your full name.' }, 400)
    }
    if (String(password ?? '').length < 8) {
      return json({ error: 'Password must be at least 8 characters.' }, 400)
    }

    const client = admin()

    const { data: existing } = await client
      .from('coordinators')
      .select('id')
      .eq('username', cleanUsername)
      .maybeSingle()
    if (existing) return json({ error: 'That username is already taken.' }, 409)

    const email = `coordinator-${crypto.randomUUID()}@accounts.eventx.invalid`
    const { data: created, error: createError } = await client.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { username: cleanUsername, name: cleanName, role: 'coordinator' },
    })
    if (createError || !created.user) throw createError ?? new Error('user_create_failed')
    userId = created.user.id

    const { error: profileError } = await client
      .from('coordinators')
      .insert({ id: userId, username: cleanUsername, name: cleanName })
    if (profileError) throw profileError

    const session = await issueSession(email)
    return json({ username: cleanUsername, ...session }, 201)
  } catch (error) {
    console.error(error)
    if (userId) await admin().auth.admin.deleteUser(userId)
    const message =
      error instanceof Error && error.message.toLowerCase().includes('duplicate')
        ? 'That username is already taken.'
        : 'Account creation could not be completed.'
    return json({ error: message }, 400)
  }
})
