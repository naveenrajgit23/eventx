-- ============================================================
-- HOTFIX: publishing winners must auto-close registration
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
