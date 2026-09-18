-- ============================================================
-- EVENT MANAGEMENT SYSTEM
-- SUPABASE COMPLETE DATABASE REBUILD - V3
-- ============================================================
--
-- FIXES:
-- 1. set_updated_at trigger dependency
-- 2. gen_random_bytes() problem
-- 3. save_score parameter-name conflict
-- 4. winner "position" naming problem
--
-- ============================================================


-- ============================================================
-- 1. DROP TRIGGERS FIRST
-- ============================================================

DROP TRIGGER IF EXISTS events_updated_at
ON public.events;

DROP TRIGGER IF EXISTS rounds_updated_at
ON public.rounds;

DROP TRIGGER IF EXISTS scores_updated_at
ON public.scores;

DROP TRIGGER IF EXISTS participant_sessions_updated_at
ON public.participant_sessions;


-- ============================================================
-- 2. DROP OLD FUNCTIONS
-- ============================================================

DROP FUNCTION IF EXISTS public.coordinator_dashboard_stats();

DROP FUNCTION IF EXISTS public.create_event(text, public.point_format);

DROP FUNCTION IF EXISTS public.save_score(uuid, uuid, integer, jsonb);

DROP FUNCTION IF EXISTS public.set_round_status(uuid, public.round_status);

DROP FUNCTION IF EXISTS public.announce_round_result(uuid);

DROP FUNCTION IF EXISTS public.set_registration_status(uuid, boolean);

DROP FUNCTION IF EXISTS public.generate_round_two(uuid, text, integer, uuid[]);

DROP FUNCTION IF EXISTS public.event_leaderboard(uuid);

DROP FUNCTION IF EXISTS public.publish_winners(uuid);
DROP FUNCTION IF EXISTS public.publish_winners(uuid, integer);

DROP FUNCTION IF EXISTS public.public_winners();

DROP FUNCTION IF EXISTS public.create_participant_team(text, text, text);

DROP FUNCTION IF EXISTS public.verify_participant_login(text, text);

DROP FUNCTION IF EXISTS public.participant_leaderboard(uuid);

DROP FUNCTION IF EXISTS public.participant_dashboard(uuid);

DROP FUNCTION IF EXISTS public.is_event_owner(uuid);

DROP FUNCTION IF EXISTS public.set_updated_at();


-- ============================================================
-- 3. DROP OLD TABLES
-- ============================================================

DROP TABLE IF EXISTS public.participant_sessions CASCADE;

DROP TABLE IF EXISTS public.audit_logs CASCADE;

DROP TABLE IF EXISTS public.winner_announcements CASCADE;

DROP TABLE IF EXISTS public.score_details CASCADE;

DROP TABLE IF EXISTS public.scores CASCADE;

DROP TABLE IF EXISTS public.round_teams CASCADE;

DROP TABLE IF EXISTS public.rounds CASCADE;

DROP TABLE IF EXISTS public.teams CASCADE;

DROP TABLE IF EXISTS public.scoring_rules CASCADE;

DROP TABLE IF EXISTS public.events CASCADE;

DROP TABLE IF EXISTS public.coordinators CASCADE;


-- ============================================================
-- 4. DROP OLD ENUMS
-- ============================================================

DROP TYPE IF EXISTS public.point_format CASCADE;

DROP TYPE IF EXISTS public.event_status CASCADE;

DROP TYPE IF EXISTS public.round_status CASCADE;


-- ============================================================
-- 5. EXTENSIONS
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE EXTENSION IF NOT EXISTS citext;


-- ============================================================
-- 6. ENUMS
-- ============================================================

CREATE TYPE public.point_format AS ENUM (
    'robo_race',
    'drone_race'
);


CREATE TYPE public.event_status AS ENUM (
    'draft',
    'registration_open',
    'registration_closed',
    'round_1_active',
    'round_1_completed',
    'round_2_selection',
    'round_2_active',
    'completed'
);


CREATE TYPE public.round_status AS ENUM (
    'not_started',
    'active',
    'completed',
    'locked'
);


-- ============================================================
-- 7. COORDINATORS
-- ============================================================

CREATE TABLE public.coordinators (

    id UUID PRIMARY KEY
        REFERENCES auth.users(id)
        ON DELETE CASCADE,

    username CITEXT NOT NULL UNIQUE,

    name TEXT NOT NULL,

    email TEXT,

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT now()
);


-- ============================================================
-- 8. EVENTS
-- ============================================================

CREATE TABLE public.events (

    id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    event_name TEXT NOT NULL,

    event_code CITEXT NOT NULL UNIQUE,

    point_format public.point_format NOT NULL,

    created_by UUID NOT NULL
        REFERENCES public.coordinators(id)
        ON DELETE CASCADE,

    status public.event_status NOT NULL
        DEFAULT 'registration_open',

    -- Independent of `status`: round/qualification progress must never
    -- implicitly open or close registration. Only set_registration_status()
    -- changes this, and only an explicit coordinator action calls it.
    registration_closed BOOLEAN NOT NULL
        DEFAULT false,

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT now(),

    updated_at TIMESTAMPTZ NOT NULL
        DEFAULT now()
);


-- ============================================================
-- 9. SCORING RULES
-- ============================================================

CREATE TABLE public.scoring_rules (

    id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    event_id UUID NOT NULL
        REFERENCES public.events(id)
        ON DELETE CASCADE,

    rule_key TEXT NOT NULL,

    rule_name TEXT NOT NULL,

    rule_type TEXT NOT NULL
        CHECK (
            rule_type IN (
                'penalty',
                'bonus'
            )
        ),

    seconds INTEGER NOT NULL
        CHECK (seconds >= 0),

    operation TEXT NOT NULL
        CHECK (
            operation IN (
                'add',
                'subtract'
            )
        ),

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT now(),

    UNIQUE (
        event_id,
        rule_key
    )
);


-- ============================================================
-- 10. TEAMS
-- ============================================================

CREATE TABLE public.teams (

    id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    event_id UUID NOT NULL
        REFERENCES public.events(id)
        ON DELETE CASCADE,

    team_name TEXT NOT NULL,

    team_code CITEXT NOT NULL UNIQUE,

    phone_number TEXT,

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT now(),

    UNIQUE (
        event_id,
        team_name
    )
);


-- ============================================================
-- 11. ROUNDS
-- ============================================================

CREATE TABLE public.rounds (

    id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    event_id UUID NOT NULL
        REFERENCES public.events(id)
        ON DELETE CASCADE,

    round_number INTEGER NOT NULL
        CHECK (
            round_number IN (1, 2)
        ),

    round_name TEXT NOT NULL,

    status public.round_status NOT NULL
        DEFAULT 'not_started',

    result_announced BOOLEAN NOT NULL
        DEFAULT false,

    announced_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT now(),

    updated_at TIMESTAMPTZ NOT NULL
        DEFAULT now(),

    UNIQUE (
        event_id,
        round_number
    )
);


-- ============================================================
-- 12. ROUND TEAMS
-- ============================================================

CREATE TABLE public.round_teams (

    id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    round_id UUID NOT NULL
        REFERENCES public.rounds(id)
        ON DELETE CASCADE,

    team_id UUID NOT NULL
        REFERENCES public.teams(id)
        ON DELETE CASCADE,

    qualification_type TEXT
        CHECK (
            qualification_type IS NULL
            OR qualification_type IN (
                'automatic_top_n',
                'manual'
            )
        ),

    qualified BOOLEAN NOT NULL
        DEFAULT true,

    UNIQUE (
        round_id,
        team_id
    )
);


-- ============================================================
-- 13. SCORES
-- ============================================================

CREATE TABLE public.scores (

    id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    round_id UUID NOT NULL
        REFERENCES public.rounds(id)
        ON DELETE CASCADE,

    team_id UUID NOT NULL
        REFERENCES public.teams(id)
        ON DELETE CASCADE,

    total_time_seconds INTEGER NOT NULL
        CHECK (
            total_time_seconds >= 0
        ),

    final_score_seconds INTEGER NOT NULL
        CHECK (
            final_score_seconds >= 0
        ),

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT now(),

    updated_at TIMESTAMPTZ NOT NULL
        DEFAULT now(),

    UNIQUE (
        round_id,
        team_id
    )
);


-- ============================================================
-- 14. SCORE DETAILS
-- ============================================================

CREATE TABLE public.score_details (

    id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    score_id UUID NOT NULL
        REFERENCES public.scores(id)
        ON DELETE CASCADE,

    rule_id UUID NOT NULL
        REFERENCES public.scoring_rules(id)
        ON DELETE CASCADE,

    quantity INTEGER NOT NULL
        DEFAULT 0
        CHECK (
            quantity >= 0
        ),

    calculated_seconds INTEGER NOT NULL
        DEFAULT 0,

    UNIQUE (
        score_id,
        rule_id
    )
);


-- ============================================================
-- 15. WINNER ANNOUNCEMENTS
-- ============================================================

CREATE TABLE public.winner_announcements (

    id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    event_id UUID NOT NULL
        REFERENCES public.events(id)
        ON DELETE CASCADE,

    team_id UUID NOT NULL
        REFERENCES public.teams(id)
        ON DELETE CASCADE,

    winner_position INTEGER NOT NULL
        CHECK (
            winner_position > 0
        ),

    published BOOLEAN NOT NULL
        DEFAULT false,

    published_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT now(),

    UNIQUE (
        event_id,
        winner_position
    ),

    UNIQUE (
        event_id,
        team_id
    )
);


-- ============================================================
-- 16. AUDIT LOGS
-- ============================================================

CREATE TABLE public.audit_logs (

    id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    user_id UUID,

    event_id UUID,

    action TEXT NOT NULL,

    entity_type TEXT,

    entity_id UUID,

    old_value JSONB,

    new_value JSONB,

    reason TEXT,

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT now()
);


-- ============================================================
-- 17. PARTICIPANT SESSIONS
-- ============================================================

CREATE TABLE public.participant_sessions (

    id UUID PRIMARY KEY
        DEFAULT gen_random_uuid(),

    team_id UUID NOT NULL
        REFERENCES public.teams(id)
        ON DELETE CASCADE,

    token_hash TEXT NOT NULL UNIQUE,

    expires_at TIMESTAMPTZ NOT NULL,

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT now(),

    updated_at TIMESTAMPTZ NOT NULL
        DEFAULT now()
);


-- ============================================================
-- 18. INDEXES
-- ============================================================

CREATE INDEX idx_events_created_by
ON public.events(created_by);

CREATE INDEX idx_events_event_code
ON public.events(event_code);

CREATE INDEX idx_teams_event_id
ON public.teams(event_id);

CREATE INDEX idx_teams_team_code
ON public.teams(team_code);

CREATE INDEX idx_rounds_event_id
ON public.rounds(event_id);

CREATE INDEX idx_round_teams_round_id
ON public.round_teams(round_id);

CREATE INDEX idx_round_teams_team_id
ON public.round_teams(team_id);

CREATE INDEX idx_scores_round_id
ON public.scores(round_id);

CREATE INDEX idx_scores_team_id
ON public.scores(team_id);

CREATE INDEX idx_score_details_score_id
ON public.score_details(score_id);

CREATE INDEX idx_winners_event_id
ON public.winner_announcements(event_id);

CREATE INDEX idx_audit_logs_event_id
ON public.audit_logs(event_id);

CREATE INDEX idx_participant_sessions_team_id
ON public.participant_sessions(team_id);


-- ============================================================
-- 19. UPDATED_AT FUNCTION
-- ============================================================

CREATE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN

    NEW.updated_at = now();

    RETURN NEW;

END;
$$;


-- ============================================================
-- 20. TRIGGERS
-- ============================================================

CREATE TRIGGER events_updated_at

BEFORE UPDATE
ON public.events

FOR EACH ROW

EXECUTE FUNCTION public.set_updated_at();


CREATE TRIGGER rounds_updated_at

BEFORE UPDATE
ON public.rounds

FOR EACH ROW

EXECUTE FUNCTION public.set_updated_at();


CREATE TRIGGER scores_updated_at

BEFORE UPDATE
ON public.scores

FOR EACH ROW

EXECUTE FUNCTION public.set_updated_at();


CREATE TRIGGER participant_sessions_updated_at

BEFORE UPDATE
ON public.participant_sessions

FOR EACH ROW

EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- 21. EVENT OWNER
-- ============================================================

CREATE FUNCTION public.is_event_owner(
    p_event_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$

    SELECT EXISTS (

        SELECT 1

        FROM public.events e

        WHERE e.id = p_event_id

        AND e.created_by = auth.uid()

    );

$$;


-- ============================================================
-- 21B. SET REGISTRATION STATUS
-- ============================================================
-- Lets a coordinator manually open/close registration at any time.
-- Round/qualification actions (start round, announce, lock, generate
-- Round 2) never touch this column. publish_winners() is the one
-- exception -- it force-closes registration when the final podium is
-- published, since no new teams should be able to join after results
-- are official. Registration can still be reopened here afterward.

CREATE FUNCTION public.set_registration_status(
    p_event_id UUID,
    p_closed BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN

    IF NOT public.is_event_owner(
        p_event_id
    ) THEN

        RAISE EXCEPTION
            'You do not own this event';

    END IF;


    UPDATE public.events

    SET

        registration_closed = p_closed,

        updated_at = now()

    WHERE id = p_event_id;


    RETURN jsonb_build_object(

        'success',
        true,

        'event_id',
        p_event_id,

        'registration_closed',
        p_closed

    );

END;
$$;


-- ============================================================
-- 22. CREATE EVENT
-- ============================================================

CREATE FUNCTION public.create_event(
    p_event_name TEXT,
    p_point_format public.point_format
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE

    v_event_id UUID;

    v_event_code TEXT;

    v_round_id UUID;

BEGIN

    IF auth.uid() IS NULL THEN

        RAISE EXCEPTION
            'Authentication required';

    END IF;


    IF NOT EXISTS (

        SELECT 1

        FROM public.coordinators

        WHERE id = auth.uid()

    ) THEN

        RAISE EXCEPTION
            'Coordinator profile not found';

    END IF;


    IF p_event_name IS NULL
       OR trim(p_event_name) = '' THEN

        RAISE EXCEPTION
            'Event name is required';

    END IF;


    -- ========================================================
    -- UNIQUE EVENT CODE
    -- Uses UUID.
    -- NO gen_random_bytes().
    -- ========================================================

    LOOP

        v_event_code :=

            CASE

                WHEN p_point_format =
                    'robo_race'

                THEN 'ROB'

                ELSE 'DRN'

            END

            || TO_CHAR(
                CURRENT_DATE,
                'YY'
            )

            || UPPER(

                SUBSTRING(

                    REPLACE(
                        gen_random_uuid()::TEXT,
                        '-',
                        ''
                    )

                    FROM 1 FOR 4

                )

            );


        EXIT WHEN NOT EXISTS (

            SELECT 1

            FROM public.events

            WHERE event_code =
                v_event_code

        );

    END LOOP;


    -- ========================================================
    -- EVENT
    -- ========================================================

    INSERT INTO public.events (

        event_name,

        event_code,

        point_format,

        created_by,

        status

    )

    VALUES (

        trim(p_event_name),

        v_event_code,

        p_point_format,

        auth.uid(),

        'registration_open'

    )

    RETURNING id

    INTO v_event_id;


    -- ========================================================
    -- ROUND 1
    -- ========================================================

    INSERT INTO public.rounds (

        event_id,

        round_number,

        round_name,

        status

    )

    VALUES (

        v_event_id,

        1,

        'Round 1',

        'not_started'

    )

    RETURNING id

    INTO v_round_id;


    -- ========================================================
    -- ROBO RULES
    -- ========================================================

    IF p_point_format =
        'robo_race' THEN

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
    -- DRONE RULES
    -- ========================================================

    IF p_point_format =
        'drone_race' THEN

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
        ),

        (
            v_event_id,
            'perfect_landing',
            'Perfect Landing',
            'bonus',
            8,
            'subtract'
        );

    END IF;


    -- ========================================================
    -- AUDIT
    -- ========================================================

    INSERT INTO public.audit_logs (

        user_id,

        event_id,

        action,

        entity_type,

        entity_id,

        new_value

    )

    VALUES (

        auth.uid(),

        v_event_id,

        'event_created',

        'event',

        v_event_id,

        jsonb_build_object(

            'event_name',
            trim(p_event_name),

            'event_code',
            v_event_code,

            'point_format',
            p_point_format

        )

    );


    RETURN jsonb_build_object(

        'success',
        true,

        'event_id',
        v_event_id,

        'event_code',
        v_event_code,

        'event_name',
        trim(p_event_name),

        'point_format',
        p_point_format,

        'round_id',
        v_round_id

    );

END;
$$;


-- ============================================================
-- 23. SAVE SCORE
-- ============================================================

CREATE FUNCTION public.save_score(
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

        RAISE EXCEPTION
            'Authentication required';

    END IF;


    IF p_total_time_seconds IS NULL
       OR p_total_time_seconds < 0 THEN

        RAISE EXCEPTION
            'Invalid total time';

    END IF;


    SELECT

        r.event_id,

        r.status

    INTO

        v_event_id,

        v_round_status

    FROM public.rounds r

    WHERE r.id = p_round_id

    FOR UPDATE;


    IF v_event_id IS NULL THEN

        RAISE EXCEPTION
            'Round not found';

    END IF;


    IF NOT public.is_event_owner(
        v_event_id
    ) THEN

        RAISE EXCEPTION
            'You do not own this event';

    END IF;


    -- Announcing a result is informational only (see
    -- announce_round_result); only an explicit lock (status = 'locked',
    -- set via set_round_status) blocks further score entry. Round 2 never
    -- checks Round 1's announcement state at all -- each round is gated
    -- solely by its own lock status.
    IF v_round_status = 'locked' THEN

        RAISE EXCEPTION
            'This round is locked. Scores cannot be changed.';

    END IF;


    IF NOT EXISTS (

        SELECT 1

        FROM public.round_teams rt

        WHERE rt.round_id =
            p_round_id

        AND rt.team_id =
            p_team_id

        AND rt.qualified = true

    ) THEN

        RAISE EXCEPTION
            'Team is not registered for this round';

    END IF;


    -- ========================================================
    -- FINAL SCORE STARTS WITH TOTAL TIME
    -- ========================================================

    v_final_score :=
        p_total_time_seconds;


    -- ========================================================
    -- APPLY RULES
    -- ========================================================

    FOR v_rule IN

        SELECT

            sr.id,

            sr.rule_key,

            sr.seconds,

            sr.operation

        FROM public.scoring_rules sr

        WHERE sr.event_id =
            v_event_id

    LOOP


        v_quantity := COALESCE(

            (

                SELECT

                    (x.value)::INTEGER

                FROM jsonb_each_text(

                    COALESCE(

                        p_score_details,

                        '{}'::jsonb

                    )

                ) x

                WHERE x.key =
                    v_rule.rule_key

            ),

            0

        );


        IF v_quantity < 0 THEN

            RAISE EXCEPTION
                'Score quantity cannot be negative';

        END IF;


        v_calculated :=

            v_quantity
            * v_rule.seconds;


        IF v_rule.operation =
            'add' THEN

            v_final_score :=
                v_final_score
                + v_calculated;

        ELSE

            v_final_score :=
                v_final_score
                - v_calculated;

        END IF;


    END LOOP;


    IF v_final_score < 0 THEN

        v_final_score := 0;

    END IF;


    -- ========================================================
    -- SAVE
    -- ========================================================

    INSERT INTO public.scores (

        round_id,

        team_id,

        total_time_seconds,

        final_score_seconds

    )

    VALUES (

        p_round_id,

        p_team_id,

        p_total_time_seconds,

        v_final_score

    )

    ON CONFLICT (
        round_id,
        team_id
    )

    DO UPDATE SET

        total_time_seconds =
            EXCLUDED.total_time_seconds,

        final_score_seconds =
            EXCLUDED.final_score_seconds,

        updated_at =
            now()

    RETURNING id

    INTO v_score_id;


    -- ========================================================
    -- DETAILS
    -- ========================================================

    DELETE FROM public.score_details

    WHERE score_id =
        v_score_id;


    FOR v_rule IN

        SELECT

            sr.id,

            sr.rule_key,

            sr.seconds,

            sr.operation

        FROM public.scoring_rules sr

        WHERE sr.event_id =
            v_event_id

    LOOP


        v_quantity := COALESCE(

            (

                SELECT

                    (x.value)::INTEGER

                FROM jsonb_each_text(

                    COALESCE(

                        p_score_details,

                        '{}'::jsonb

                    )

                ) x

                WHERE x.key =
                    v_rule.rule_key

            ),

            0

        );


        v_calculated :=

            v_quantity
            * v_rule.seconds;


        INSERT INTO public.score_details (

            score_id,

            rule_id,

            quantity,

            calculated_seconds

        )

        VALUES (

            v_score_id,

            v_rule.id,

            v_quantity,

            v_calculated

        );

    END LOOP;


    -- ========================================================
    -- AUDIT
    -- ========================================================

    INSERT INTO public.audit_logs (

        user_id,

        event_id,

        action,

        entity_type,

        entity_id,

        new_value

    )

    VALUES (

        auth.uid(),

        v_event_id,

        'score_saved',

        'score',

        v_score_id,

        jsonb_build_object(

            'round_id',
            p_round_id,

            'team_id',
            p_team_id,

            'total_time_seconds',
            p_total_time_seconds,

            'final_score_seconds',
            v_final_score

        )

    );


    RETURN jsonb_build_object(

        'success',
        true,

        'score_id',
        v_score_id,

        'total_time_seconds',
        p_total_time_seconds,

        'final_score_seconds',
        v_final_score

    );

END;
$$;


-- ============================================================
-- 24. SET ROUND STATUS
-- ============================================================

CREATE FUNCTION public.set_round_status(
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

        RAISE EXCEPTION
            'Round not found';

    END IF;


    IF NOT public.is_event_owner(
        v_event_id
    ) THEN

        RAISE EXCEPTION
            'You do not own this event';

    END IF;


    -- A lock is the coordinator's explicit, authoritative final action --
    -- once set, it cannot be changed back through this generic status
    -- setter (matches the hard block save_score enforces on scores).
    IF v_current_status = 'locked' THEN

        RAISE EXCEPTION
            'This round is locked and its status can no longer be changed.';

    END IF;


    UPDATE public.rounds

    SET

        status = p_status,

        updated_at = now()

    WHERE id = p_round_id;


    RETURN jsonb_build_object(

        'success',
        true,

        'round_id',
        p_round_id,

        'status',
        p_status

    );

END;
$$;


-- ============================================================
-- 25. ANNOUNCE ROUND RESULT
-- ============================================================

CREATE FUNCTION public.announce_round_result(
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

    SELECT event_id

    INTO v_event_id

    FROM public.rounds

    WHERE id = p_round_id

    FOR UPDATE;


    IF v_event_id IS NULL THEN

        RAISE EXCEPTION
            'Round not found';

    END IF;


    IF NOT public.is_event_owner(
        v_event_id
    ) THEN

        RAISE EXCEPTION
            'You do not own this event';

    END IF;


    -- Announcing is informational/publication state only -- it does NOT
    -- lock the round. Scores stay editable until the coordinator explicitly
    -- locks the round via set_round_status(p_round_id, 'locked').
    UPDATE public.rounds

    SET

        result_announced = true,

        announced_at = now(),

        updated_at = now()

    WHERE id = p_round_id;


    INSERT INTO public.audit_logs (

        user_id,

        event_id,

        action,

        entity_type,

        entity_id

    )

    VALUES (

        auth.uid(),

        v_event_id,

        'round_result_announced',

        'round',

        p_round_id

    );


    RETURN jsonb_build_object(

        'success',
        true,

        'round_id',
        p_round_id,

        'result_announced',
        true

    );

END;
$$;


-- ============================================================
-- 26. EVENT LEADERBOARD
-- ============================================================

CREATE FUNCTION public.event_leaderboard(
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

        SELECT

            s.team_id,

            s.final_score_seconds AS score

        FROM public.scores s

        JOIN public.rounds r
            ON r.id = s.round_id

        WHERE r.event_id =
            p_event_id

        AND r.round_number = 1

    ),

    r2 AS (

        SELECT

            s.team_id,

            s.final_score_seconds AS score

        FROM public.scores s

        JOIN public.rounds r
            ON r.id = s.round_id

        WHERE r.event_id =
            p_event_id

        AND r.round_number = 2

    ),

    combined AS (

        SELECT

            t.id AS team_id,

            t.team_name,

            t.team_code::TEXT AS team_code,

            -- True NULL when a round has no score yet -- a missing round
            -- must read as "pending", never as a same-as-zero time.
            r1.score AS round_1_score,

            r2.score AS round_2_score,

            CASE

                WHEN r1.score IS NOT NULL
                     AND r2.score IS NOT NULL

                THEN
                    r1.score
                    + r2.score

                ELSE
                    NULL

            END AS final_score,

            -- Internal ranking helper only (never returned): a missing
            -- round must not make a team look faster, but partially
            -- scored teams still need a deterministic sort position.
            COALESCE(r1.score, 0)
            + COALESCE(r2.score, 0)
                AS sort_score

        FROM public.teams t

        LEFT JOIN r1
            ON r1.team_id = t.id

        LEFT JOIN r2
            ON r2.team_id = t.id

        WHERE t.event_id =
            p_event_id

    )

    SELECT

        c.team_id,

        c.team_name,

        c.team_code,

        c.round_1_score,

        c.round_2_score,

        c.final_score,

        ROW_NUMBER() OVER (

            ORDER BY

                c.sort_score ASC,

                c.round_2_score ASC NULLS LAST,

                c.round_1_score ASC NULLS LAST,

                c.team_id

        ) AS rank

    FROM combined c

    WHERE

        c.round_1_score IS NOT NULL

        OR c.round_2_score IS NOT NULL

    ORDER BY rank;

$$;


-- ============================================================
-- 27. GENERATE ROUND 2
-- ============================================================

CREATE FUNCTION public.generate_round_two(
    p_event_id UUID,
    p_qualification_type TEXT,
    p_top_n INTEGER DEFAULT NULL,
    p_team_ids UUID[] DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE

    v_round_id UUID;

BEGIN

    IF NOT public.is_event_owner(
        p_event_id
    ) THEN

        RAISE EXCEPTION
            'You do not own this event';

    END IF;


    SELECT id

    INTO v_round_id

    FROM public.rounds

    WHERE event_id =
        p_event_id

    AND round_number = 2;


    IF v_round_id IS NULL THEN

        INSERT INTO public.rounds (

            event_id,

            round_number,

            round_name,

            status

        )

        VALUES (

            p_event_id,

            2,

            'Round 2',

            'not_started'

        )

        RETURNING id
        INTO v_round_id;

    END IF;


    DELETE FROM public.round_teams

    WHERE round_id =
        v_round_id;


    IF p_qualification_type =
        'automatic_top_n' THEN


        IF p_top_n IS NULL
           OR p_top_n <= 0 THEN

            RAISE EXCEPTION
                'Top N must be greater than zero';

        END IF;


        INSERT INTO public.round_teams (

            round_id,

            team_id,

            qualification_type,

            qualified

        )

        SELECT

            v_round_id,

            x.team_id,

            'automatic_top_n',

            true

        FROM public.event_leaderboard(
            p_event_id
        ) x

        WHERE x.rank <=
            p_top_n;


    ELSIF p_qualification_type =
        'manual' THEN


        IF p_team_ids IS NULL
           OR array_length(
                p_team_ids,
                1
              ) IS NULL THEN

            RAISE EXCEPTION
                'Select at least one team';

        END IF;


        INSERT INTO public.round_teams (

            round_id,

            team_id,

            qualification_type,

            qualified

        )

        SELECT

            v_round_id,

            t.id,

            'manual',

            true

        FROM public.teams t

        WHERE t.event_id =
            p_event_id

        AND t.id = ANY(
            p_team_ids
        );


    ELSE

        RAISE EXCEPTION
            'Invalid qualification type';

    END IF;


    UPDATE public.events

    SET

        status =
            'round_2_selection',

        updated_at =
            now()

    WHERE id =
        p_event_id;


    RETURN jsonb_build_object(

        'success',
        true,

        'event_id',
        p_event_id,

        'round_id',
        v_round_id

    );

END;
$$;


-- ============================================================
-- 28. PUBLISH WINNERS
-- ============================================================

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

    IF NOT public.is_event_owner(
        p_event_id
    ) THEN

        RAISE EXCEPTION
            'You do not own this event';

    END IF;


    IF p_count IS NULL
       OR p_count <= 0 THEN

        RAISE EXCEPTION
            'Please select a valid winner count';

    END IF;


    IF EXISTS (

        SELECT 1

        FROM public.winner_announcements

        WHERE event_id =
            p_event_id

    ) THEN

        RAISE EXCEPTION
            'Winners have already been published for this event';

    END IF;


    SELECT r.* INTO v_highest_round

    FROM public.rounds r

    WHERE r.event_id =
        p_event_id

    ORDER BY r.round_number DESC

    LIMIT 1;


    IF v_highest_round IS NULL
       OR NOT v_highest_round.result_announced THEN

        RAISE EXCEPTION
            'Final round results must be announced and locked before publishing winners';

    END IF;


    IF NOT EXISTS (

        SELECT 1
        FROM public.event_leaderboard(p_event_id)

    ) THEN

        RAISE EXCEPTION
            'No final scores found. Please enter scores and announce the round before publishing winners';

    END IF;


    INSERT INTO public.winner_announcements (

        event_id,

        team_id,

        winner_position,

        published,

        published_at

    )

    SELECT

        p_event_id,

        x.team_id,

        x.rank,

        true,

        now()

    FROM public.event_leaderboard(
        p_event_id
    ) x

    WHERE x.rank <=
        p_count;


    UPDATE public.events

    SET

        status =
            'completed',

        registration_closed =
            true,

        updated_at =
            now()

    WHERE id =
        p_event_id;


    INSERT INTO public.audit_logs (

        user_id,

        event_id,

        action

    )

    VALUES (

        auth.uid(),

        p_event_id,

        'winners_published'

    );


    RETURN jsonb_build_object(

        'success',
        true,

        'event_id',
        p_event_id

    );

END;
$$;


-- ============================================================
-- 29. PUBLIC WINNERS
-- ============================================================

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

    JOIN public.events e
        ON e.id = w.event_id

    JOIN public.teams t
        ON t.id = w.team_id

    WHERE w.published = true

    ORDER BY

        e.created_at DESC,

        w.winner_position ASC;

$$;


-- ============================================================
-- 30. PARTICIPANT REGISTRATION
-- ============================================================

CREATE FUNCTION public.create_participant_team(
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

    IF p_team_name IS NULL
       OR trim(p_team_name) = '' THEN

        RAISE EXCEPTION
            'Team name is required';

    END IF;


    -- Registration availability is governed solely by registration_closed
    -- (toggled only via set_registration_status), independent of event.status
    -- and independent of round progress -- starting/announcing/locking a
    -- round, or generating Round 2, must never close registration.
    SELECT

        id,

        point_format

    INTO

        v_event_id,

        v_point_format

    FROM public.events

    WHERE event_code =
        trim(p_event_code)

    AND registration_closed = false;


    IF v_event_id IS NULL THEN

        RAISE EXCEPTION
            'Invalid event code or registration is closed';

    END IF;


    IF EXISTS (

        SELECT 1

        FROM public.teams

        WHERE event_id =
            v_event_id

        AND LOWER(team_name) =
            LOWER(trim(p_team_name))

    ) THEN

        RAISE EXCEPTION
            'Team name already registered';

    END IF;


    v_prefix :=

        CASE

            WHEN v_point_format =
                'robo_race'

            THEN 'ROB-'

            ELSE 'DRN-'

        END;


    SELECT

        COALESCE(

            MAX(

                CASE

                    WHEN team_code::TEXT
                        ~ '[0-9]+$'

                    THEN

                        substring(
                            team_code::TEXT
                            from '[0-9]+$'
                        )::INTEGER

                    ELSE 0

                END

            ),

            0

        ) + 1

    INTO v_number

    FROM public.teams

    WHERE event_id =
        v_event_id;


    v_team_code :=

        v_prefix

        || LPAD(
            v_number::TEXT,
            3,
            '0'
        );


    INSERT INTO public.teams (

        event_id,

        team_name,

        team_code,

        phone_number

    )

    VALUES (

        v_event_id,

        trim(p_team_name),

        v_team_code,

        NULLIF(
            trim(
                COALESCE(
                    p_phone_number,
                    ''
                )
            ),
            ''
        )

    )

    RETURNING id
    INTO v_team_id;


    -- Round 1 registration

    INSERT INTO public.round_teams (

        round_id,

        team_id,

        qualification_type,

        qualified

    )

    SELECT

        r.id,

        v_team_id,

        'manual',

        true

    FROM public.rounds r

    WHERE r.event_id =
        v_event_id

    AND r.round_number = 1;


    RETURN jsonb_build_object(

        'success',
        true,

        'team_id',
        v_team_id,

        'team_name',
        trim(p_team_name),

        'team_code',
        v_team_code,

        'event_id',
        v_event_id,

        'event_code',
        trim(p_event_code)

    );

END;
$$;


-- ============================================================
-- 31. PARTICIPANT LOGIN
-- ============================================================
--
-- Uses UUID.
-- NO gen_random_bytes().
--
-- ============================================================

CREATE FUNCTION public.verify_participant_login(
    p_team_name TEXT,
    p_team_code TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE

    v_team_id UUID;

    v_event_id UUID;

    v_token TEXT;

    v_token_hash TEXT;

BEGIN

    SELECT

        t.id,

        t.event_id

    INTO

        v_team_id,

        v_event_id

    FROM public.teams t

    WHERE LOWER(t.team_name) =
        LOWER(trim(p_team_name))

    AND t.team_code =
        trim(p_team_code);


    IF v_team_id IS NULL THEN

        RAISE EXCEPTION
            'Invalid team name or team code';

    END IF;


    -- UUID token

    v_token :=

        REPLACE(
            gen_random_uuid()::TEXT,
            '-',
            ''
        )

        ||

        REPLACE(
            gen_random_uuid()::TEXT,
            '-',
            ''
        );


    -- SHA256

    v_token_hash :=

        ENCODE(

            DIGEST(
                v_token,
                'sha256'
            ),

            'hex'

        );


    -- Remove old sessions

    DELETE FROM public.participant_sessions

    WHERE team_id =
        v_team_id;


    -- New session

    INSERT INTO public.participant_sessions (

        team_id,

        token_hash,

        expires_at

    )

    VALUES (

        v_team_id,

        v_token_hash,

        now() + interval '7 days'

    );


    RETURN jsonb_build_object(

        'success',
        true,

        'team_id',
        v_team_id,

        'event_id',
        v_event_id,

        'token',
        v_token,

        'expires_at',
        now() + interval '7 days'

    );

END;
$$;


-- ============================================================
-- 32. PARTICIPANT LEADERBOARD
-- ============================================================

CREATE FUNCTION public.participant_leaderboard(
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

    SELECT *

    FROM public.event_leaderboard(
        p_event_id
    );

$$;


-- ============================================================
-- 33. PARTICIPANT DASHBOARD
-- ============================================================

CREATE FUNCTION public.participant_dashboard(
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

    SELECT

        event_id

    INTO

        v_event_id

    FROM public.teams

    WHERE id =
        p_team_id;


    IF v_event_id IS NULL THEN

        RAISE EXCEPTION
            'Team not found';

    END IF;


    -- Round status

    SELECT

        COALESCE(

            jsonb_agg(

                jsonb_build_object(

                    'round_number',
                    r.round_number,

                    'round_name',
                    r.round_name,

                    'status',
                    r.status,

                    'result_announced',
                    r.result_announced,

                    'announced_at',
                    r.announced_at

                )

                ORDER BY
                    r.round_number

            ),

            '[]'::jsonb

        )

    INTO v_rounds

    FROM public.rounds r

    WHERE r.event_id =
        v_event_id;


    v_round_2_configured := EXISTS (
        SELECT 1
        FROM public.rounds r
        WHERE r.event_id = v_event_id
        AND r.round_number = 2
    );


    -- Event details (nested under team, matching what the dashboard reads)

    SELECT

        jsonb_build_object(
            'event_name', e.event_name,
            'event_code', e.event_code,
            'point_format', e.point_format,
            'rounds', v_rounds
        )

    INTO v_event

    FROM public.events e

    WHERE e.id =
        v_event_id;


    v_is_round_2_qualified := EXISTS (
        SELECT 1
        FROM public.round_teams rt
        JOIN public.rounds r ON r.id = rt.round_id
        WHERE rt.team_id = p_team_id
        AND r.round_number = 2
        AND rt.qualified
    );


    SELECT w.winner_position

    INTO v_winner_position

    FROM public.winner_announcements w

    WHERE w.team_id = p_team_id

    AND w.event_id = v_event_id

    AND w.published

    LIMIT 1;


    -- Team details

    SELECT

        jsonb_build_object(

            'id',
            t.id,

            'team_name',
            t.team_name,

            'team_code',
            t.team_code,

            'phone_number',
            t.phone_number,

            'event_id',
            t.event_id,

            'is_round_2_qualified',
            v_is_round_2_qualified,

            'winner_position',
            v_winner_position,

            'events',
            v_event

        )

    INTO v_team

    FROM public.teams t

    WHERE t.id =
        p_team_id;


    -- Leaderboard

    SELECT

        COALESCE(

            jsonb_agg(

                jsonb_build_object(

                    'team_id',
                    x.team_id,

                    'team_name',
                    x.team_name,

                    'team_code',
                    x.team_code,

                    'round_1_score',
                    x.round_1_score,

                    'round_2_score',
                    x.round_2_score,

                    'final_score',
                    x.final_score,

                    'rank',
                    x.rank

                )

                ORDER BY x.rank

            ),

            '[]'::jsonb

        )

    INTO v_leaderboard

    FROM public.event_leaderboard(
        v_event_id
    ) x;


    -- Published winners (empty until the coordinator publishes them)

    SELECT

        COALESCE(

            jsonb_agg(

                jsonb_build_object(

                    'winner_position',
                    w.winner_position,

                    'team_id',
                    w.team_id,

                    'team_name',
                    t.team_name,

                    'team_code',
                    t.team_code,

                    'final_score',
                    x.final_score

                )

                ORDER BY w.winner_position

            ),

            '[]'::jsonb

        )

    INTO v_winners

    FROM public.winner_announcements w

    JOIN public.teams t ON t.id = w.team_id

    LEFT JOIN public.event_leaderboard(v_event_id) x ON x.team_id = w.team_id

    WHERE w.event_id = v_event_id

    AND w.published;


    RETURN jsonb_build_object(

        'success',
        true,

        'team',
        v_team,

        'rounds',
        v_rounds,

        'leaderboard',
        v_leaderboard,

        'winners',
        v_winners,

        'round_2_configured',
        v_round_2_configured

    );

END;
$$;


-- ============================================================
-- 34. COORDINATOR DASHBOARD STATS
-- ============================================================

CREATE FUNCTION public.coordinator_dashboard_stats()
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$

    SELECT jsonb_build_object(

        'events',

        (

            SELECT COUNT(*)

            FROM public.events

            WHERE created_by =
                auth.uid()

        ),

        'teams',

        (

            SELECT COUNT(*)

            FROM public.teams t

            JOIN public.events e
                ON e.id = t.event_id

            WHERE e.created_by =
                auth.uid()

        ),

        'active_events',

        (

            SELECT COUNT(*)

            FROM public.events

            WHERE created_by =
                auth.uid()

            AND status <> 'completed'

        ),

        'completed_events',

        (

            SELECT COUNT(*)

            FROM public.events

            WHERE created_by =
                auth.uid()

            AND status = 'completed'

        )

    );

$$;


-- ============================================================
-- 35. RLS
-- ============================================================

ALTER TABLE public.coordinators
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.events
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.scoring_rules
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.teams
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.rounds
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.round_teams
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.scores
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.score_details
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.winner_announcements
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.audit_logs
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.participant_sessions
ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- 36. POLICIES
-- ============================================================

CREATE POLICY coordinator_read_own_profile

ON public.coordinators

FOR SELECT

TO authenticated

USING (
    id = auth.uid()
);


CREATE POLICY coordinator_read_own_events

ON public.events

FOR SELECT

TO authenticated

USING (
    created_by = auth.uid()
);


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
-- 37. TABLE PERMISSIONS
-- ============================================================

REVOKE ALL
ON public.coordinators
FROM anon;

REVOKE ALL
ON public.events
FROM anon;

REVOKE ALL
ON public.scoring_rules
FROM anon;

REVOKE ALL
ON public.teams
FROM anon;

REVOKE ALL
ON public.rounds
FROM anon;

REVOKE ALL
ON public.round_teams
FROM anon;

REVOKE ALL
ON public.scores
FROM anon;

REVOKE ALL
ON public.score_details
FROM anon;

REVOKE ALL
ON public.winner_announcements
FROM anon;

REVOKE ALL
ON public.audit_logs
FROM anon;

REVOKE ALL
ON public.participant_sessions
FROM anon;


-- ============================================================
-- 38. RPC PERMISSIONS
-- ============================================================

GRANT EXECUTE
ON FUNCTION public.create_event(
    TEXT,
    public.point_format
)
TO authenticated;


GRANT EXECUTE
ON FUNCTION public.save_score(
    UUID,
    UUID,
    INTEGER,
    JSONB
)
TO authenticated;


GRANT EXECUTE
ON FUNCTION public.set_round_status(
    UUID,
    public.round_status
)
TO authenticated;


GRANT EXECUTE
ON FUNCTION public.announce_round_result(
    UUID
)
TO authenticated;


GRANT EXECUTE
ON FUNCTION public.set_registration_status(
    UUID,
    BOOLEAN
)
TO authenticated;


GRANT EXECUTE
ON FUNCTION public.generate_round_two(
    UUID,
    TEXT,
    INTEGER,
    UUID[]
)
TO authenticated;


GRANT EXECUTE
ON FUNCTION public.event_leaderboard(
    UUID
)
TO authenticated;


GRANT EXECUTE
ON FUNCTION public.publish_winners(
    UUID,
    INTEGER
)
TO authenticated;


GRANT EXECUTE
ON FUNCTION public.coordinator_dashboard_stats()
TO authenticated;


GRANT EXECUTE
ON FUNCTION public.create_participant_team(
    TEXT,
    TEXT,
    TEXT
)
TO anon, authenticated;


GRANT EXECUTE
ON FUNCTION public.verify_participant_login(
    TEXT,
    TEXT
)
TO anon, authenticated;


GRANT EXECUTE
ON FUNCTION public.participant_leaderboard(
    UUID
)
TO anon, authenticated;


GRANT EXECUTE
ON FUNCTION public.participant_dashboard(
    UUID
)
TO anon, authenticated;


GRANT EXECUTE
ON FUNCTION public.public_winners()
TO anon, authenticated;


-- ============================================================
-- 39. VERIFY TABLES
-- ============================================================

SELECT
    table_name

FROM information_schema.tables

WHERE table_schema = 'public'

AND table_name IN (

    'coordinators',
    'events',
    'scoring_rules',
    'teams',
    'rounds',
    'round_teams',
    'scores',
    'score_details',
    'winner_announcements',
    'audit_logs',
    'participant_sessions'

)

ORDER BY table_name;


-- ============================================================
-- 40. VERIFY FUNCTIONS
-- ============================================================

SELECT

    p.proname AS function_name,

    pg_get_function_arguments(p.oid)
        AS arguments

FROM pg_proc p

JOIN pg_namespace n
    ON n.oid = p.pronamespace

WHERE n.nspname = 'public'

AND p.proname IN (

    'create_event',
    'save_score',
    'set_round_status',
    'announce_round_result',
    'generate_round_two',
    'event_leaderboard',
    'publish_winners',
    'public_winners',
    'create_participant_team',
    'verify_participant_login',
    'participant_leaderboard',
    'participant_dashboard',
    'coordinator_dashboard_stats'

)

ORDER BY p.proname;


-- ============================================================
-- 41. CHECK FOR gen_random_bytes
-- ============================================================

SELECT
    CASE
        WHEN COUNT(*) = 0
        THEN 'OK - gen_random_bytes is not used'
        ELSE 'ERROR - gen_random_bytes still exists'
    END AS check_result

FROM pg_proc p

JOIN pg_namespace n
    ON n.oid = p.pronamespace

WHERE p.proname = 'gen_random_bytes'
AND n.nspname = 'public';


-- ============================================================
-- 42. FINAL STATUS
-- ============================================================

SELECT
    'EVENT MANAGEMENT DATABASE READY' AS status;