alter table public.profiles enable row level security;alter table public.coordinators enable row level security;alter table public.events enable row level security;alter table public.scoring_rules enable row level security;alter table public.teams enable row level security;alter table public.participant_credentials enable row level security;alter table public.rounds enable row level security;alter table public.round_teams enable row level security;alter table public.scores enable row level security;alter table public.score_details enable row level security;alter table public.winner_announcements enable row level security;alter table public.audit_logs enable row level security;

create policy "profile self read" on public.profiles for select to authenticated using(id=auth.uid());
create policy "coordinator self read" on public.coordinators for select to authenticated using(id=auth.uid());
create policy "events coordinator manage" on public.events for all to authenticated using(created_by=auth.uid()) with check(created_by=auth.uid());
create policy "participant reads own event" on public.events for select to authenticated using(public.is_participant_in_event(id));
create policy "public reads winning events" on public.events for select to anon,authenticated using(exists(select 1 from public.winner_announcements w where w.event_id=id and w.published));
create policy "rules owner read" on public.scoring_rules for select to authenticated using(public.is_event_owner(event_id));
create policy "rules participant read" on public.scoring_rules for select to authenticated using(public.is_participant_in_event(event_id));
create policy "teams owner manage" on public.teams for all to authenticated using(public.is_event_owner(event_id)) with check(public.is_event_owner(event_id));
create policy "participant reads own team" on public.teams for select to authenticated using(public.is_current_team(id));
create policy "participant reads announced peers" on public.teams for select to authenticated using(public.is_participant_in_event(event_id) and exists(select 1 from public.rounds r where r.event_id=teams.event_id and r.result_announced));
create policy "public reads winner teams" on public.teams for select to anon,authenticated using(exists(select 1 from public.winner_announcements w where w.team_id=id and w.published));
create policy "rounds owner manage" on public.rounds for all to authenticated using(public.is_event_owner(event_id)) with check(public.is_event_owner(event_id));
create policy "participant reads event rounds" on public.rounds for select to authenticated using(public.is_participant_in_event(event_id));
create policy "round teams owner manage" on public.round_teams for all to authenticated using(exists(select 1 from public.rounds r where r.id=round_id and public.is_event_owner(r.event_id))) with check(exists(select 1 from public.rounds r where r.id=round_id and public.is_event_owner(r.event_id)));
create policy "participant reads qualifications" on public.round_teams for select to authenticated using(public.is_current_team(team_id));
create policy "scores owner read" on public.scores for select to authenticated using(exists(select 1 from public.rounds r where r.id=round_id and public.is_event_owner(r.event_id)));
create policy "scores participant announced read" on public.scores for select to authenticated using(exists(select 1 from public.rounds r where r.id=round_id and r.result_announced and public.is_participant_in_event(r.event_id)));
create policy "details owner read" on public.score_details for select to authenticated using(exists(select 1 from public.scores s join public.rounds r on r.id=s.round_id where s.id=score_id and public.is_event_owner(r.event_id)));
create policy "winner owner manage" on public.winner_announcements for all to authenticated using(public.is_event_owner(event_id)) with check(public.is_event_owner(event_id));
create policy "published winners public read" on public.winner_announcements for select to anon,authenticated using(published=true);
create policy "audit owner read" on public.audit_logs for select to authenticated using(public.is_event_owner(event_id));

revoke insert,update,delete on public.scores,public.score_details from anon,authenticated;
revoke all on public.participant_credentials from anon,authenticated;
grant select on public.published_winners to anon,authenticated;
