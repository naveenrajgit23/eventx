-- ============================================================
-- FIX: participant team registration fails with HTTP 400
-- ============================================================
--
-- Root cause: create_participant_team() generated the next team_code
-- number scoped to the CURRENT EVENT only (MAX(...) WHERE event_id =
-- v_event_id), but teams.team_code carries a table-wide UNIQUE
-- constraint (teams_team_code_key), not one scoped per event. So the
-- first robo_race team registered for any new event tried to insert
-- "ROB-001" again and collided with a team already registered under
-- an earlier event, raising:
--
--   duplicate key value violates unique constraint "teams_team_code_key"
--
-- which register-team's Edge Function catches and reports as the
-- generic "Team registration could not be completed." (HTTP 400) for
-- every single registration after the first event of a given point
-- format was created.
--
-- Fix: compute the next number across ALL teams sharing the same
-- prefix (globally), matching the actual scope of the unique
-- constraint, and retry on a unique_violation to close the race
-- window between the SELECT MAX and the INSERT under concurrent
-- registrations. Signature, return shape, and RAISE EXCEPTION message
-- text are unchanged so the Edge Function's error mapping keeps
-- working.
-- ============================================================

CREATE OR REPLACE FUNCTION public.create_participant_team(
    p_team_name TEXT,
    p_phone_number TEXT,
    p_event_code TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
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

    LOOP
        SELECT COALESCE(MAX(
            CASE WHEN team_code::TEXT ~ '[0-9]+$'
                 THEN substring(team_code::TEXT from '[0-9]+$')::INTEGER
                 ELSE 0 END
        ), 0) + 1
        INTO v_number
        FROM public.teams
        WHERE team_code::TEXT LIKE v_prefix || '%';

        v_team_code := v_prefix || LPAD(v_number::TEXT, 3, '0');

        BEGIN
            INSERT INTO public.teams (event_id, team_name, team_code, phone_number)
            VALUES (
                v_event_id,
                trim(p_team_name),
                v_team_code,
                NULLIF(trim(COALESCE(p_phone_number, '')), '')
            )
            RETURNING id INTO v_team_id;
            EXIT;
        EXCEPTION WHEN unique_violation THEN
            -- Another concurrent registration just took this code; retry with the next number.
            CONTINUE;
        END;
    END LOOP;

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
$function$;
