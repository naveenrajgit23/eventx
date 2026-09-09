-- ============================================================
-- RUN THIS ONE FILE IN THE SUPABASE SQL EDITOR.
-- ============================================================
-- This combines every pending hotfix in this folder into a single
-- script, in the correct order, so you only have to paste and run
-- once instead of hunting down file order yourself.
--
-- It is 100% ADDITIVE / NON-DESTRUCTIVE:
--   - No DROP TABLE, no DELETE, no data is touched or lost.
--   - Every function uses CREATE OR REPLACE (or DROP FUNCTION on the
--     exact old signature immediately followed by CREATE) so it only
--     replaces function *definitions*, never rows.
--   - registration_closed is added with IF NOT EXISTS and a safe
--     default, so existing events are unaffected.
--   - It is idempotent: safe to run more than once if you're ever
--     unsure whether it already ran.
--
-- What this fixes, in order:
--
-- PART 1 (was supabase/fix_live_scoring_flow.sql)
--   Registration was being blocked by events.status instead of its
--   own column. generate_round_two() sets events.status =
--   'round_2_selection' once Round 2 is configured, and the old
--   create_participant_team() required events.status =
--   'registration_open' -- so the moment a coordinator configured
--   Round 2, every new team registration failed with "Invalid event
--   code or registration is closed", even though nobody closed
--   registration. THIS IS THE BUG YOU ARE HITTING RIGHT NOW.
--   This part also separates "announce result" from "lock round"
--   (announcing no longer silently blocks further scoring), and makes
--   the leaderboard report a truly unscored round as NULL/"Pending"
--   instead of a fabricated 0.
--
-- PART 2 (was supabase/fix_missing_rls_policies.sql)
--   teams / scoring_rules / rounds / round_teams / scores /
--   score_details have Row Level Security enabled but were missing
--   SELECT policies, so the coordinator dashboard silently got back
--   empty results for all of them instead of an error.
--
-- PART 3 (was supabase/fix_participant_dashboard.sql)
--   participant_dashboard() never returned winners, round_2_configured,
--   or the team's nested event/rounds data, so the participant
--   dashboard's winner banner, Round 2 selection banner, and round
--   status cards never worked. public_winners() also never returned
--   point_format, leaving a blank format label on the public winners
--   page.
--
-- PART 4 (was supabase/fix_publish_winners_closes_registration.sql)
--   publish_winners() was deployed with a signature the frontend
--   couldn't call correctly ("Could not find the function... in the
--   schema cache"), and even when called never inserted the winner
--   rows in the first place. This replaces it with a version that
--   actually inserts winners, and also auto-closes registration when
--   winners are published (so no one can join after results are
--   sealed).
--
-- PART 5 (new)
--   The deployed Edge Functions (register-team, participant-login)
--   link a team to a real Supabase Auth user via teams.user_id, and
--   verify_participant_login() needs to return that user's id so
--   participant-login can look up their email and mint a session.
--   Neither existed in this schema. Adds teams.user_id (nullable --
--   existing teams registered before this fix simply won't be able
--   to log back in via the login *form* until they re-register; any
--   already-open browser session for them is unaffected, since that
--   only needs the team_id already embedded in their session token)
--   and replaces verify_participant_login to return it.
-- ============================================================


-- ============================================================
-- PART 1: independent registration + explicit round locking +
-- NULL-safe leaderboard
-- ============================================================

ALTER TABLE public.events
ADD COLUMN IF NOT EXISTS registration_closed BOOLEAN NOT NULL DEFAULT false;


CREATE OR REPLACE FUNCTION public.set_registration_status(
    p_event_id UUID,
    p_closed BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NOT public.is_event_owner(p_event_id) THEN
        RAISE EXCEPTION 'You do not own this event';
    END IF;

    UPDATE public.events
    SET registration_closed = p_closed, updated_at = now()
    WHERE id = p_event_id;

    RETURN jsonb_build_object(
        'success', true,
        'event_id', p_event_id,
        'registration_closed', p_closed
    );
END;
$$;

GRANT EXECUTE
ON FUNCTION public.set_registration_status(UUID, BOOLEAN)
TO authenticated;


CREATE OR REPLACE FUNCTION public.create_participant_team(
    p_team_name TEXT,
    p_phone_number TEXT,
    p_event_code TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_event_id UUID;
    v_point_format public.point_format;
    v_team_id UUID;
    v_team_code TEXT;
    v_prefix TEXT;
    v_number INTEGER;
BEGIN
    IF p_team_name IS NULL OR trim(p_team_name) = '' THEN
        RAISE EXCEPTION 'Team name is required';
    END IF;

    SELECT id, point_format
    INTO v_event_id, v_point_format
    FROM public.events
    WHERE event_code = trim(p_event_code)
    AND registration_closed = false;

    IF v_event_id IS NULL THEN
        RAISE EXCEPTION 'Invalid event code or registration is closed';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.teams
        WHERE event_id = v_event_id
        AND LOWER(team_name) = LOWER(trim(p_team_name))
    ) THEN
        RAISE EXCEPTION 'Team name already registered';
    END IF;

    v_prefix := CASE WHEN v_point_format = 'robo_race' THEN 'ROB-' ELSE 'DRN-' END;

    SELECT COALESCE(MAX(
        CASE WHEN team_code::TEXT ~ '[0-9]+$'
             THEN substring(team_code::TEXT from '[0-9]+$')::INTEGER
             ELSE 0 END
    ), 0) + 1
    INTO v_number
    FROM public.teams
    WHERE event_id = v_event_id;

    v_team_code := v_prefix || LPAD(v_number::TEXT, 3, '0');

    INSERT INTO public.teams (event_id, team_name, team_code, phone_number)
    VALUES (
        v_event_id,
        trim(p_team_name),
        v_team_code,
        NULLIF(trim(COALESCE(p_phone_number, '')), '')
    )
    RETURNING id INTO v_team_id;

    -- Round 1 registration -- unconditional, regardless of Round 1's
    -- status, so a team registering after Round 1 has started is
    -- immediately eligible for scoring (unless Round 1 is locked, in
    -- which case save_score's own lock check applies like it does for
    -- every other team).
    INSERT INTO public.round_teams (round_id, team_id, qualification_type, qualified)
    SELECT r.id, v_team_id, 'manual', true
    FROM public.rounds r
    WHERE r.event_id = v_event_id
    AND r.round_number = 1;

    RETURN jsonb_build_object(
        'success', true,
        'team_id', v_team_id,
        'team_name', trim(p_team_name),
        'team_code', v_team_code,
        'event_id', v_event_id,
        'event_code', trim(p_event_code)
    );
END;
$$;


CREATE OR REPLACE FUNCTION public.save_score(
    p_round_id UUID,
    p_team_id UUID,
    p_total_time_seconds INTEGER,
    p_score_details JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_event_id UUID;
    v_round_status public.round_status;
    v_score_id UUID;
    v_final_score INTEGER;
    v_rule RECORD;
    v_quantity INTEGER;
    v_calculated INTEGER;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF p_total_time_seconds IS NULL OR p_total_time_seconds < 0 THEN
        RAISE EXCEPTION 'Invalid total time';
    END IF;

    SELECT r.event_id, r.status
    INTO v_event_id, v_round_status
    FROM public.rounds r
    WHERE r.id = p_round_id
    FOR UPDATE;

    IF v_event_id IS NULL THEN
        RAISE EXCEPTION 'Round not found';
    END IF;

    IF NOT public.is_event_owner(v_event_id) THEN
        RAISE EXCEPTION 'You do not own this event';
    END IF;

    -- Only an explicit lock blocks scoring now -- announcing a result
    -- no longer does, and Round 2 was never gated on Round 1 here.
    IF v_round_status = 'locked' THEN
        RAISE EXCEPTION 'This round is locked. Scores cannot be changed.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.round_teams rt
        WHERE rt.round_id = p_round_id
        AND rt.team_id = p_team_id
        AND rt.qualified = true
    ) THEN
        RAISE EXCEPTION 'Team is not registered for this round';
    END IF;

    v_final_score := p_total_time_seconds;

    FOR v_rule IN
        SELECT sr.id, sr.rule_key, sr.seconds, sr.operation
        FROM public.scoring_rules sr
        WHERE sr.event_id = v_event_id
    LOOP
        v_quantity := COALESCE((
            SELECT (x.value)::INTEGER
            FROM jsonb_each_text(COALESCE(p_score_details, '{}'::jsonb)) x
            WHERE x.key = v_rule.rule_key
        ), 0);

        IF v_quantity < 0 THEN
            RAISE EXCEPTION 'Score quantity cannot be negative';
        END IF;

        v_calculated := v_quantity * v_rule.seconds;

        IF v_rule.operation = 'add' THEN
            v_final_score := v_final_score + v_calculated;
        ELSE
            v_final_score := v_final_score - v_calculated;
        END IF;
    END LOOP;

    IF v_final_score < 0 THEN
        v_final_score := 0;
    END IF;

    INSERT INTO public.scores (round_id, team_id, total_time_seconds, final_score_seconds)
    VALUES (p_round_id, p_team_id, p_total_time_seconds, v_final_score)
    ON CONFLICT (round_id, team_id)
    DO UPDATE SET
        total_time_seconds = EXCLUDED.total_time_seconds,
        final_score_seconds = EXCLUDED.final_score_seconds,
        updated_at = now()
    RETURNING id INTO v_score_id;

    DELETE FROM public.score_details WHERE score_id = v_score_id;

    FOR v_rule IN
        SELECT sr.id, sr.rule_key, sr.seconds, sr.operation
        FROM public.scoring_rules sr
        WHERE sr.event_id = v_event_id
    LOOP
        v_quantity := COALESCE((
            SELECT (x.value)::INTEGER
            FROM jsonb_each_text(COALESCE(p_score_details, '{}'::jsonb)) x
            WHERE x.key = v_rule.rule_key
        ), 0);

        v_calculated := v_quantity * v_rule.seconds;

        INSERT INTO public.score_details (score_id, rule_id, quantity, calculated_seconds)
        VALUES (v_score_id, v_rule.id, v_quantity, v_calculated);
    END LOOP;

    INSERT INTO public.audit_logs (user_id, event_id, action, entity_type, entity_id, new_value)
    VALUES (
        auth.uid(), v_event_id, 'score_saved', 'score', v_score_id,
        jsonb_build_object(
            'round_id', p_round_id,
            'team_id', p_team_id,
            'total_time_seconds', p_total_time_seconds,
            'final_score_seconds', v_final_score
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'score_id', v_score_id,
        'total_time_seconds', p_total_time_seconds,
        'final_score_seconds', v_final_score
    );
END;
$$;


CREATE OR REPLACE FUNCTION public.set_round_status(
    p_round_id UUID,
    p_status public.round_status
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_event_id UUID;
    v_current_status public.round_status;
BEGIN
    SELECT event_id, status
    INTO v_event_id, v_current_status
    FROM public.rounds
    WHERE id = p_round_id
    FOR UPDATE;

    IF v_event_id IS NULL THEN
        RAISE EXCEPTION 'Round not found';
    END IF;

    IF NOT public.is_event_owner(v_event_id) THEN
        RAISE EXCEPTION 'You do not own this event';
    END IF;

    -- A lock is the coordinator's explicit, final action -- once set,
    -- it cannot be changed back through this generic status setter.
    IF v_current_status = 'locked' THEN
        RAISE EXCEPTION 'This round is locked and its status can no longer be changed.';
    END IF;

    UPDATE public.rounds
    SET status = p_status, updated_at = now()
    WHERE id = p_round_id;

    RETURN jsonb_build_object(
        'success', true,
        'round_id', p_round_id,
        'status', p_status
    );
END;
$$;


CREATE OR REPLACE FUNCTION public.announce_round_result(
    p_round_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_event_id UUID;
BEGIN
    SELECT event_id INTO v_event_id
    FROM public.rounds
    WHERE id = p_round_id
    FOR UPDATE;

    IF v_event_id IS NULL THEN
        RAISE EXCEPTION 'Round not found';
    END IF;

    IF NOT public.is_event_owner(v_event_id) THEN
        RAISE EXCEPTION 'You do not own this event';
    END IF;

    -- Informational/publication state only -- does NOT lock the round.
    UPDATE public.rounds
    SET result_announced = true, announced_at = now(), updated_at = now()
    WHERE id = p_round_id;

    INSERT INTO public.audit_logs (user_id, event_id, action, entity_type, entity_id)
    VALUES (auth.uid(), v_event_id, 'round_result_announced', 'round', p_round_id);

    RETURN jsonb_build_object(
        'success', true,
        'round_id', p_round_id,
        'result_announced', true
    );
END;
$$;


CREATE OR REPLACE FUNCTION public.event_leaderboard(
    p_event_id UUID
)
RETURNS TABLE (
    team_id UUID,
    team_name TEXT,
    team_code TEXT,
    round_1_score INTEGER,
    round_2_score INTEGER,
    final_score INTEGER,
    rank BIGINT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
    WITH r1 AS (
        SELECT s.team_id, s.final_score_seconds AS score
        FROM public.scores s
        JOIN public.rounds r ON r.id = s.round_id
        WHERE r.event_id = p_event_id AND r.round_number = 1
    ),
    r2 AS (
        SELECT s.team_id, s.final_score_seconds AS score
        FROM public.scores s
        JOIN public.rounds r ON r.id = s.round_id
        WHERE r.event_id = p_event_id AND r.round_number = 2
    ),
    combined AS (
        SELECT
            t.id AS team_id,
            t.team_name,
            t.team_code::TEXT AS team_code,
            r1.score AS round_1_score,
            r2.score AS round_2_score,
            CASE WHEN r1.score IS NOT NULL AND r2.score IS NOT NULL
                 THEN r1.score + r2.score
                 ELSE NULL END AS final_score,
            COALESCE(r1.score, 0) + COALESCE(r2.score, 0) AS sort_score
        FROM public.teams t
        LEFT JOIN r1 ON r1.team_id = t.id
        LEFT JOIN r2 ON r2.team_id = t.id
        WHERE t.event_id = p_event_id
    )
    SELECT
        c.team_id, c.team_name, c.team_code,
        c.round_1_score, c.round_2_score, c.final_score,
        ROW_NUMBER() OVER (
            ORDER BY c.sort_score ASC, c.round_2_score ASC NULLS LAST,
                     c.round_1_score ASC NULLS LAST, c.team_id
        ) AS rank
    FROM combined c
    WHERE c.round_1_score IS NOT NULL OR c.round_2_score IS NOT NULL
    ORDER BY rank;
$$;


-- ============================================================
-- PART 2: missing coordinator RLS SELECT policies
-- ============================================================

DROP POLICY IF EXISTS coordinator_read_own_teams ON public.teams;

CREATE POLICY coordinator_read_own_teams
ON public.teams
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.events e
        WHERE e.id = teams.event_id
        AND e.created_by = auth.uid()
    )
);


DROP POLICY IF EXISTS coordinator_read_own_scoring_rules ON public.scoring_rules;

CREATE POLICY coordinator_read_own_scoring_rules
ON public.scoring_rules
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.events e
        WHERE e.id = scoring_rules.event_id
        AND e.created_by = auth.uid()
    )
);


DROP POLICY IF EXISTS coordinator_read_own_rounds ON public.rounds;

CREATE POLICY coordinator_read_own_rounds
ON public.rounds
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.events e
        WHERE e.id = rounds.event_id
        AND e.created_by = auth.uid()
    )
);


DROP POLICY IF EXISTS coordinator_read_own_round_teams ON public.round_teams;

CREATE POLICY coordinator_read_own_round_teams
ON public.round_teams
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.rounds r
        JOIN public.events e ON e.id = r.event_id
        WHERE r.id = round_teams.round_id
        AND e.created_by = auth.uid()
    )
);


DROP POLICY IF EXISTS coordinator_read_own_scores ON public.scores;

CREATE POLICY coordinator_read_own_scores
ON public.scores
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.rounds r
        JOIN public.events e ON e.id = r.event_id
        WHERE r.id = scores.round_id
        AND e.created_by = auth.uid()
    )
);


DROP POLICY IF EXISTS coordinator_read_own_score_details ON public.score_details;

CREATE POLICY coordinator_read_own_score_details
ON public.score_details
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.scores s
        JOIN public.rounds r ON r.id = s.round_id
        JOIN public.events e ON e.id = r.event_id
        WHERE s.id = score_details.score_id
        AND e.created_by = auth.uid()
    )
);


-- ============================================================
-- PART 3: participant dashboard missing winners/round-2/event data
-- ============================================================

CREATE OR REPLACE FUNCTION public.participant_dashboard(
    p_team_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_event_id UUID;
    v_event JSONB;
    v_team JSONB;
    v_rounds JSONB;
    v_leaderboard JSONB;
    v_winners JSONB;
    v_is_round_2_qualified BOOLEAN;
    v_winner_position INTEGER;
    v_round_2_configured BOOLEAN;
BEGIN
    SELECT event_id INTO v_event_id
    FROM public.teams
    WHERE id = p_team_id;

    IF v_event_id IS NULL THEN
        RAISE EXCEPTION 'Team not found';
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'round_number', r.round_number,
        'round_name', r.round_name,
        'status', r.status,
        'result_announced', r.result_announced,
        'announced_at', r.announced_at
    ) ORDER BY r.round_number), '[]'::jsonb)
    INTO v_rounds
    FROM public.rounds r
    WHERE r.event_id = v_event_id;

    v_round_2_configured := EXISTS (
        SELECT 1 FROM public.rounds r
        WHERE r.event_id = v_event_id AND r.round_number = 2
    );

    SELECT jsonb_build_object(
        'event_name', e.event_name,
        'event_code', e.event_code,
        'point_format', e.point_format,
        'rounds', v_rounds
    )
    INTO v_event
    FROM public.events e
    WHERE e.id = v_event_id;

    v_is_round_2_qualified := EXISTS (
        SELECT 1
        FROM public.round_teams rt
        JOIN public.rounds r ON r.id = rt.round_id
        WHERE rt.team_id = p_team_id
        AND r.round_number = 2
        AND rt.qualified
    );

    SELECT w.winner_position INTO v_winner_position
    FROM public.winner_announcements w
    WHERE w.team_id = p_team_id
    AND w.event_id = v_event_id
    AND w.published
    LIMIT 1;

    SELECT jsonb_build_object(
        'id', t.id,
        'team_name', t.team_name,
        'team_code', t.team_code,
        'phone_number', t.phone_number,
        'event_id', t.event_id,
        'is_round_2_qualified', v_is_round_2_qualified,
        'winner_position', v_winner_position,
        'events', v_event
    )
    INTO v_team
    FROM public.teams t
    WHERE t.id = p_team_id;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'team_id', x.team_id,
        'team_name', x.team_name,
        'team_code', x.team_code,
        'round_1_score', x.round_1_score,
        'round_2_score', x.round_2_score,
        'final_score', x.final_score,
        'rank', x.rank
    ) ORDER BY x.rank), '[]'::jsonb)
    INTO v_leaderboard
    FROM public.event_leaderboard(v_event_id) x;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'winner_position', w.winner_position,
        'team_id', w.team_id,
        'team_name', t.team_name,
        'team_code', t.team_code,
        'final_score', x.final_score
    ) ORDER BY w.winner_position), '[]'::jsonb)
    INTO v_winners
    FROM public.winner_announcements w
    JOIN public.teams t ON t.id = w.team_id
    LEFT JOIN public.event_leaderboard(v_event_id) x ON x.team_id = w.team_id
    WHERE w.event_id = v_event_id
    AND w.published;

    RETURN jsonb_build_object(
        'success', true,
        'team', v_team,
        'rounds', v_rounds,
        'leaderboard', v_leaderboard,
        'winners', v_winners,
        'round_2_configured', v_round_2_configured
    );
END;
$$;

GRANT EXECUTE
ON FUNCTION public.participant_dashboard(UUID)
TO anon, authenticated;


DROP FUNCTION IF EXISTS public.public_winners();

CREATE FUNCTION public.public_winners()
RETURNS TABLE (
    event_id UUID,
    event_name TEXT,
    event_code TEXT,
    point_format public.point_format,
    team_name TEXT,
    winner_position INTEGER,
    published_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT
        e.id,
        e.event_name,
        e.event_code::TEXT,
        e.point_format,
        t.team_name,
        w.winner_position,
        w.published_at
    FROM public.winner_announcements w
    JOIN public.events e ON e.id = w.event_id
    JOIN public.teams t ON t.id = w.team_id
    WHERE w.published = true
    ORDER BY e.created_at DESC, w.winner_position ASC;
$$;

GRANT EXECUTE
ON FUNCTION public.public_winners()
TO anon, authenticated;


-- ============================================================
-- PART 4: publish_winners signature fix + auto-close registration
-- ============================================================

DROP FUNCTION IF EXISTS public.publish_winners(uuid);
DROP FUNCTION IF EXISTS public.publish_winners(uuid, integer);

CREATE FUNCTION public.publish_winners(
    p_event_id UUID,
    p_count INTEGER DEFAULT 3
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_highest_round public.rounds;
BEGIN
    IF NOT public.is_event_owner(p_event_id) THEN
        RAISE EXCEPTION 'You do not own this event';
    END IF;

    IF p_count IS NULL OR p_count <= 0 THEN
        RAISE EXCEPTION 'Please select a valid winner count';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.winner_announcements WHERE event_id = p_event_id
    ) THEN
        RAISE EXCEPTION 'Winners have already been published for this event';
    END IF;

    SELECT r.* INTO v_highest_round
    FROM public.rounds r
    WHERE r.event_id = p_event_id
    ORDER BY r.round_number DESC
    LIMIT 1;

    IF v_highest_round IS NULL OR NOT v_highest_round.result_announced THEN
        RAISE EXCEPTION 'Final round results must be announced and locked before publishing winners';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.event_leaderboard(p_event_id)
    ) THEN
        RAISE EXCEPTION 'No final scores found. Please enter scores and announce the round before publishing winners';
    END IF;

    INSERT INTO public.winner_announcements (
        event_id, team_id, winner_position, published, published_at
    )
    SELECT p_event_id, x.team_id, x.rank, true, now()
    FROM public.event_leaderboard(p_event_id) x
    WHERE x.rank <= p_count;

    UPDATE public.events
    SET status = 'completed', registration_closed = true, updated_at = now()
    WHERE id = p_event_id;

    INSERT INTO public.audit_logs (user_id, event_id, action)
    VALUES (auth.uid(), p_event_id, 'winners_published');

    RETURN jsonb_build_object('success', true, 'event_id', p_event_id);
END;
$$;

GRANT EXECUTE
ON FUNCTION public.publish_winners(UUID, INTEGER)
TO authenticated;


-- ============================================================
-- PART 5: link teams to a real auth user + fix verify_participant_login
-- ============================================================

ALTER TABLE public.teams
ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;

DROP FUNCTION IF EXISTS public.verify_participant_login(text, text);

CREATE FUNCTION public.verify_participant_login(
    p_team_name TEXT,
    p_team_code TEXT
)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT t.user_id
    FROM public.teams t
    WHERE LOWER(t.team_name) = LOWER(trim(p_team_name))
    AND t.team_code = trim(p_team_code)
    LIMIT 1;
$$;

GRANT EXECUTE
ON FUNCTION public.verify_participant_login(TEXT, TEXT)
TO anon, authenticated;


-- ============================================================
-- DONE. If this ran with no red error output, every fix above is
-- now live. Refresh the app and try registering a new team after
-- Round 2 has started -- it should succeed.
--
-- IMPORTANT: this only fixes the DATABASE side. The register-team /
-- participant-login / coordinator-login / coordinator-register Edge
-- Functions currently deployed on your project do NOT match the code
-- in this repo (verified by direct testing) -- you also need to
-- redeploy them from supabase/functions/ via the Supabase CLI. See
-- the chat instructions for the exact commands.
-- ============================================================
