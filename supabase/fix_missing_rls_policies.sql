-- ============================================================
-- HOTFIX: missing coordinator RLS SELECT policies
-- ============================================================
-- Root cause: public.teams, public.scoring_rules, public.rounds,
-- public.round_teams, public.scores and public.score_details all
-- have Row Level Security ENABLED, but only public.coordinators
-- and public.events ever got a SELECT policy. With RLS on and no
-- policy, Postgres returns zero rows to every request instead of
-- an error -- so the coordinator dashboard's teams/rounds/scores
-- queries succeed with HTTP 200 and just come back empty, even
-- though the rows exist (e.g. a team that just registered).
--
-- This script is ADDITIVE ONLY: it does not drop or alter any
-- table, so it is safe to run directly against production without
-- touching existing data. It is idempotent (safe to run more than
-- once). It mirrors the policies also added to
-- event_management_database.sql so a future full rebuild stays in
-- sync.
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
