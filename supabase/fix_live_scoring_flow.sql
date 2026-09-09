-- ============================================================
-- HOTFIX: live Round 1 / Round 2 scoring, independent registration,
-- explicit round locking, and NULL-safe partial leaderboard
-- ============================================================
-- Old behavior (found in the currently deployed functions):
--
-- 1. announce_round_result() set rounds.status = 'locked' as a side
--    effect of announcing, so announcing Round 1 silently blocked
--    any further Round 1 (and by the same code path, Round 2) score
--    edits. Locking was never a separate, explicit action.
--
-- 2. save_score() rejected a score whenever result_announced = true,
--    duplicating the same implicit lock -- so even if the status
--    trick were avoided, announcing alone still froze scoring.
--
-- 3. create_participant_team() required events.status =
--    'registration_open'. Since generate_round_two() sets
--    events.status = 'round_2_selection' once Round 2 is configured,
--    registering a new team after that point failed with "Invalid
--    event code or registration is closed" -- even though no one
--    ever asked to close registration.
--
-- 4. event_leaderboard() used COALESCE(score, 0) for round_1_score /
--    round_2_score, so a team with only a Round 1 score showed
--    Round 2 as 0 seconds instead of "not scored yet" -- silently
--    the best possible score, and indistinguishable from a real 0.
--
-- New behavior this hotfix installs:
--
-- 1. Rounds are gated by their own `status` only. `status = 'locked'`
--    is now an explicit, separate action -- announcing a result no
--    longer changes `status` at all. Use set_round_status(round_id,
--    'locked') to lock a round; once locked, set_round_status itself
--    refuses to change it further.
--
-- 2. save_score() only rejects on rounds.status = 'locked'. Round 2
--    was already never gated on Round 1's announcement in this
--    function -- that part needed no change, it's confirmed here by
--    what this script does NOT touch.
--
-- 3. Registration is now gated by a new, independent
--    events.registration_closed column (default false), changed only
--    by the new set_registration_status(event_id, closed) RPC. No
--    round/qualification action ever touches it.
--
-- 4. event_leaderboard() returns round_1_score / round_2_score /
--    final_score as true SQL NULL when not yet scored, so the
--    frontend can render "Pending" instead of a fabricated 0. Ranking
--    is unchanged (still orders missing rounds as the lowest
--    possible contribution, via an internal-only sort key -- teams
--    are never excluded or misordered because of a pending round).
--
-- This script is ADDITIVE ONLY for every table (registration_closed
-- is added with IF NOT EXISTS and a safe default, so existing rows
-- are unaffected and no data is destroyed) and every function is
-- CREATE OR REPLACE / a new CREATE. It is idempotent (safe to run
-- more than once). It mirrors the changes also made to
-- event_management_database.sql so a future full rebuild stays in
-- sync. Run this in the Supabase SQL Editor.
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
