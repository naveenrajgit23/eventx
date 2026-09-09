# EVENTX

EVENTX is a responsive, multi-page competition platform for Robo Race and Drone Race events. The frontend uses HTML, CSS, and modular vanilla JavaScript. Supabase provides authentication, PostgreSQL persistence, Row Level Security, authoritative score calculations, participant sessions, round locking, and public winner announcements.

## Local setup

1. Install dependencies with `npm install`.
2. Copy `.env.example` to `.env` and add the Supabase project URL and anon key.
3. In the Supabase SQL editor, run `supabase/event_management_database.sql`. It is safe to re-run — it creates every table, RPC function, trigger, and Row Level Security policy the app needs.
4. Deploy the Edge Functions:
   - `supabase functions deploy coordinator-register`
   - `supabase functions deploy coordinator-login`
   - `supabase functions deploy register-team`
   - `supabase functions deploy participant-login`
5. Run `npm run dev` and open the URL shown by Vite.

The service-role key is used only inside Supabase Edge Functions through the platform-provided secret. Never place it in `.env` or browser code.

## Competition time format

Time input uses `minutes.seconds`, not decimal minutes: `3.56` means 3 minutes 56 seconds (236 seconds). Authoritative values are stored as integer seconds.

## Security model

- Coordinators register with username, name, and password. A hidden synthetic email is generated only inside the Edge Function because Supabase Auth requires an internal identifier; it is never requested from or displayed to the coordinator.
- Participant accounts are created server-side. A team logs in with its team name and team code, verified by the `verify_participant_login` database function, which then returns a standard Supabase session (via a server-minted magic link, never a password the participant has to know).
- Browser users cannot insert, update, or delete scores directly. The `save_score` function validates event, team, round, rule, and qualification membership before calculating the authoritative result.
- Database triggers reject score and detail updates/deletes after a result is announced, even when called outside the UI.
- Public winner data comes only from published announcements, via the `public_winners` database function.

## Quality checks

Run `npm test` for the required Robo Race and Drone Race examples. Run `npm run build` for the production bundle.
