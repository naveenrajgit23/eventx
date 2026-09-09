import { corsHeaders, json } from '../_shared/cors.ts'
import { admin, anon } from '../_shared/session.ts'

Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)

  try {
    const { username, password } = await req.json()
    const cleanUsername = String(username ?? '').trim()
    if (!cleanUsername || !password) return json({ error: 'invalid_credentials' }, 401)

    const service = admin()
    const { data: coordinator } = await service
      .from('coordinators')
      .select('id')
      .eq('username', cleanUsername)
      .maybeSingle()
    if (!coordinator) return json({ error: 'invalid_credentials' }, 401)

    const { data: userResult, error: userError } = await service.auth.admin.getUserById(coordinator.id)
    if (userError || !userResult.user?.email) return json({ error: 'invalid_credentials' }, 401)

    const { data, error } = await anon().auth.signInWithPassword({
      email: userResult.user.email,
      password,
    })
    if (error || !data.session || data.user?.user_metadata?.role !== 'coordinator') {
      return json({ error: 'invalid_credentials' }, 401)
    }

    return json({ access_token: data.session.access_token, refresh_token: data.session.refresh_token })
  } catch (error) {
    console.error(error)
    return json({ error: 'invalid_credentials' }, 401)
  }
})
