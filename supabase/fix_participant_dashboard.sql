-- ============================================================
-- HOTFIX: participant dashboard missing winners/round-2/event data
-- ============================================================
-- Root cause: public.participant_dashboard(uuid) only ever returned
-- {success, team, rounds, leaderboard}. The frontend (js/app.js,
-- renderParticipant/syncParticipantData) reads payload.winners,
-- payload.round_2_configured, team.events (nested event_name /
-- event_code / point_format / rounds), team.is_round_2_qualified
-- and team.winner_position -- none of which the function ever
-- produced. So for every participant, the winner announcement
-- banner and podium never appeared (payload.winners was always
-- undefined, defaulting to []), the "Selected for Round 2" banner
-- never appeared, and the round status cards always showed "Round 1
-- Not Started" regardless of the real round status, because
-- team.events?.rounds was always undefined.
--
-- Also fixes public.public_winners(): it never returned
-- point_format, so the public "Hall of victory" page rendered a
-- blank/wrong format label above each event's winners (the winner
-- rows themselves still showed).
--
-- This script is ADDITIVE ONLY -- it does not drop or alter any
-- table, so it is safe to run directly against production without
-- touching existing data. It is idempotent (safe to run more than
-- once). It mirrors the change also made to
-- event_management_database.sql so a future full rebuild stays in
-- sync. Run this in the Supabase SQL Editor.
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
