-- ============================================================
-- fix_robo_rules.sql
--
-- PURPOSE:
--   Update the Robo Race penalty rules for new events.
--   Drops and recreates the create_event() function with the
--   new 5-rule Robo Race penalty set:
--
--   Rule              | key                  | seconds | was
--   ------------------+----------------------+---------+-----
--   Line Touch        | line_touch           |       2 |   2  (unchanged)
--   Out of Line       | out_of_line          |       5 |   NEW
--   Complete Bot Exit | completely_bot_exit  |      20 |   5
--   Hand Touch        | hand_touch           |      10 |   3
--   Obstacle Skip     | obstacle_skip        |      25 |  10
--
-- SCOPE:
--   * Only affects NEW events created after this migration is run.
--   * Existing events keep their current scoring_rules rows
--     (historical scores are NOT recalculated).
--   * Drone Race rules are UNCHANGED.
--   * save_score() and event_leaderboard() are UNCHANGED
--     (they read scoring_rules at runtime, no hardcoded values).
--
-- TEST CASE:
--   Total = 236 s, line_touch=5, out_of_line=2,
--   completely_bot_exit=1, hand_touch=1, obstacle_skip=1
--   => 236 + 10 + 10 + 20 + 10 + 25 = 311 s (5 min 11 sec)
-- ============================================================

DROP FUNCTION IF EXISTS public.create_event(text, public.point_format);


CREATE FUNCTION public.create_event(
    p_event_name  TEXT,
    p_point_format public.point_format
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE

    v_event_id   UUID;
    v_event_code TEXT;
    v_prefix     TEXT;

BEGIN

    -- --------------------------------------------------------
    -- VALIDATE INPUTS
    -- --------------------------------------------------------

    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.coordinators WHERE id = auth.uid()
    ) THEN
        RAISE EXCEPTION 'Only coordinators can create events.';
    END IF;

    IF length(trim(p_event_name)) < 2
    OR length(trim(p_event_name)) > 120 THEN
        RAISE EXCEPTION 'invalid_event_name';
    END IF;


    -- --------------------------------------------------------
    -- GENERATE UNIQUE EVENT CODE
    -- --------------------------------------------------------

    v_prefix := CASE
        WHEN p_point_format = 'robo_race'  THEN 'ROB'
        WHEN p_point_format = 'drone_race' THEN 'DRN'
    END;

    LOOP
        v_event_code := v_prefix
            || '-'
            || upper(substring(encode(gen_random_bytes(3), 'hex') FROM 1 FOR 6));
        EXIT WHEN NOT EXISTS (
            SELECT 1 FROM public.events WHERE event_code = v_event_code
        );
    END LOOP;


    -- --------------------------------------------------------
    -- INSERT EVENT
    -- --------------------------------------------------------

    INSERT INTO public.events (
        created_by,
        event_name,
        event_code,
        point_format
    )
    VALUES (
        auth.uid(),
        trim(p_event_name),
        v_event_code,
        p_point_format
    )
    RETURNING id INTO v_event_id;


    -- ========================================================
    -- ROBO RULES (updated 2026-09-17)
    -- ========================================================

    IF p_point_format = 'robo_race' THEN

        INSERT INTO public.scoring_rules (
            event_id,
            rule_key,
            rule_name,
            rule_type,
            seconds,
            operation
        )
        VALUES

        (
            v_event_id,
            'line_touch',
            'Line Touch',
            'penalty',
            2,
            'add'
        ),

        (
            v_event_id,
            'out_of_line',
            'Out of Line',
            'penalty',
            5,
            'add'
        ),

        (
            v_event_id,
            'completely_bot_exit',
            'Complete Bot Exit',
            'penalty',
            20,
            'add'
        ),

        (
            v_event_id,
            'hand_touch',
            'Hand Touch',
            'penalty',
            10,
            'add'
        ),

        (
            v_event_id,
            'obstacle_skip',
            'Obstacle Skip',
            'penalty',
            25,
            'add'
        );

    END IF;


    -- ========================================================
    -- DRONE RULES (unchanged)
    -- ========================================================

    IF p_point_format = 'drone_race' THEN

        INSERT INTO public.scoring_rules (
            event_id,
            rule_key,
            rule_name,
            rule_type,
            seconds,
            operation
        )
        VALUES

        (
            v_event_id,
            'ground_touch',
            'Ground Touch',
            'penalty',
            5,
            'add'
        ),

        (
            v_event_id,
            'obstacle_hit',
            'Obstacle Hit',
            'penalty',
            4,
            'add'
        ),

        (
            v_event_id,
            'obstacle_miss',
            'Obstacle Miss',
            'penalty',
            8,
            'add'
        ),

        (
            v_event_id,
            'bonus',
            'Bonus',
            'bonus',
            1,
            'subtract'
            'hand_touch',
            'Hand Touch',
            'penalty',
            5,
            'add'
        ),

        (
            v_event_id,
            'perfect_landing',
            'Perfect Landing',
            'bonus',
            8,
            'subtract'
            'landing_miss',
            'Landing Miss',
            'penalty',
            5,
            'add'
        );

    END IF;


    -- --------------------------------------------------------
    -- RETURN
    -- --------------------------------------------------------

    RETURN jsonb_build_object(
        'event_id',   v_event_id,
        'event_code', v_event_code
    );

END;
$$;