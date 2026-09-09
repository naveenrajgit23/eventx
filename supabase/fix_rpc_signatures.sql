-- ============================================================
-- HOTFIX: RPC parameter mismatches + broken publish_winners
-- ============================================================
-- 1. generate_round_two: no DB change needed. The frontend was
--    calling it with a "p_method" parameter but the function has
--    always taken "p_qualification_type" -- fixed in js/rounds.js.
--
-- 2. save_score: no DB change needed. The frontend was calling it
--    with "p_details" (an array of {rule_id, quantity}) but the
--    function has always taken "p_score_details" (a flat JSONB
--    object keyed by each rule's rule_key, e.g.
--    {"line_touch": 2, "hand_touch": 1}) -- fixed in js/scores.js
--    and js/app.js.
--
-- 3. publish_winners: the frontend calls it with p_event_id AND
--    p_count, but the deployed function only accepted p_event_id
--    -- so PostgREST could never resolve the call ("Could not find
--    the function ... in the schema cache"). On top of that, the
--    deployed function only ever UPDATEd public.winner_announcements
--    to set published = true; nothing ever INSERTed the winner rows
--    in the first place, so publishing would have been a no-op even
--    if the parameter names had matched. This patch replaces
--    publish_winners with a version that takes p_count, validates
--    (event ownership, valid count, not already published, final
--    round announced, at least one scored team), inserts the top
--    p_count teams from event_leaderboard() as winner_announcements
--    rows, and marks the event completed.
--
-- This script is ADDITIVE ONLY -- it does not drop or alter any
-- table, so it is safe to run directly against production without
-- touching existing data. It is idempotent (safe to run more than
-- once). It mirrors the change also made to
-- event_management_database.sql so a future full rebuild stays in
-- sync. Run this in the Supabase SQL Editor.
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
    SET status = 'completed', updated_at = now()
    WHERE id = p_event_id;

    INSERT INTO public.audit_logs (user_id, event_id, action)
    VALUES (auth.uid(), p_event_id, 'winners_published');

    RETURN jsonb_build_object('success', true, 'event_id', p_event_id);

END;
$$;

GRANT EXECUTE
ON FUNCTION public.publish_winners(UUID, INTEGER)
TO authenticated;
