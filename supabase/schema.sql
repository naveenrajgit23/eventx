create extension if not exists pgcrypto;
create extension if not exists citext;

create type public.user_role as enum ('coordinator','participant');
create type public.point_format as enum ('robo_race','drone_race');
create type public.event_status as enum ('draft','registration_open','registration_closed','round_1_active','round_1_completed','round_2_selection','round_2_active','completed');
create type public.round_status as enum ('not_started','active','completed','locked');
create type public.rule_type as enum ('penalty','bonus');
create type public.rule_operation as enum ('add','subtract');
create type public.qualification_type as enum ('automatic_top_n','manual');

create table public.profiles(id uuid primary key references auth.users(id) on delete cascade,name text not null,role public.user_role not null,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.coordinators(id uuid primary key references public.profiles(id) on delete cascade,username citext not null unique,email citext not null unique,created_at timestamptz not null default now());
create table public.events(id uuid primary key default gen_random_uuid(),event_name text not null check(length(event_name) between 2 and 120),event_code citext not null unique,point_format public.point_format not null,created_by uuid not null references public.coordinators(id),status public.event_status not null default 'registration_open',created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.scoring_rules(id uuid primary key default gen_random_uuid(),event_id uuid not null references public.events(id) on delete cascade,rule_key text not null,rule_name text not null,rule_type public.rule_type not null,seconds integer not null check(seconds>=0),operation public.rule_operation not null,created_at timestamptz not null default now(),unique(event_id,rule_key));
create table public.teams(id uuid primary key default gen_random_uuid(),event_id uuid not null references public.events(id) on delete restrict,auth_user_id uuid unique references auth.users(id) on delete set null,team_name text not null check(length(team_name) between 2 and 100),team_code citext not null unique,phone_number text not null check(length(phone_number) between 7 and 20),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(event_id,team_name));
create table public.participant_credentials(team_id uuid primary key references public.teams(id) on delete cascade,code_hash text not null,failed_attempts integer not null default 0,locked_until timestamptz,created_at timestamptz not null default now());
create table public.rounds(id uuid primary key default gen_random_uuid(),event_id uuid not null references public.events(id) on delete cascade,round_number smallint not null check(round_number in(1,2)),round_name text not null,status public.round_status not null default 'not_started',result_announced boolean not null default false,announced_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(event_id,round_number));
create table public.round_teams(id uuid primary key default gen_random_uuid(),round_id uuid not null references public.rounds(id) on delete cascade,team_id uuid not null references public.teams(id) on delete cascade,qualification_type public.qualification_type,qualified boolean not null default true,created_at timestamptz not null default now(),unique(round_id,team_id));
create table public.scores(id uuid primary key default gen_random_uuid(),round_id uuid not null references public.rounds(id) on delete restrict,team_id uuid not null references public.teams(id) on delete restrict,total_time_seconds integer not null check(total_time_seconds>=0),final_score_seconds integer not null check(final_score_seconds>=0),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(round_id,team_id));
create table public.score_details(id uuid primary key default gen_random_uuid(),score_id uuid not null references public.scores(id) on delete cascade,rule_id uuid not null references public.scoring_rules(id) on delete restrict,quantity integer not null check(quantity>=0),calculated_seconds integer not null check(calculated_seconds>=0),created_at timestamptz not null default now(),unique(score_id,rule_id));
create table public.winner_announcements(id uuid primary key default gen_random_uuid(),event_id uuid not null references public.events(id) on delete restrict,team_id uuid not null references public.teams(id) on delete restrict,position smallint not null check(position between 1 and 4),published boolean not null default false,published_at timestamptz,created_at timestamptz not null default now(),unique(event_id,position),unique(event_id,team_id));
create table public.audit_logs(id bigint generated always as identity primary key,user_id uuid,event_id uuid references public.events(id),action text not null,entity_type text not null,entity_id uuid,old_value jsonb,new_value jsonb,reason text,created_at timestamptz not null default now());
create index on public.events(created_by);create index on public.teams(event_id);create index on public.rounds(event_id);create index on public.round_teams(round_id,qualified);create index on public.scores(round_id,final_score_seconds);create index on public.winner_announcements(event_id,published);

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path='' as $$
begin
  insert into public.profiles(id,name,role) values(new.id,coalesce(new.raw_user_meta_data->>'name','Participant'),coalesce((new.raw_user_meta_data->>'role')::public.user_role,'participant'));
  if new.raw_user_meta_data->>'role'='coordinator' then insert into public.coordinators(id,username,email) values(new.id,new.raw_user_meta_data->>'username',new.email); end if;
  return new;
end$$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.reject_locked_score_change() returns trigger language plpgsql set search_path='' as $$
declare rid uuid;
begin rid:=case when tg_op='DELETE' then old.round_id else new.round_id end;if exists(select 1 from public.rounds where id=rid and result_announced) then raise exception 'round_locked' using errcode='P0001';end if;if tg_op='DELETE' then return old;else return new;end if;end$$;
create trigger scores_locked_guard before update or delete on public.scores for each row execute function public.reject_locked_score_change();
create or replace function public.reject_locked_detail_change() returns trigger language plpgsql set search_path='' as $$
declare sid uuid;begin sid:=case when tg_op='DELETE' then old.score_id else new.score_id end;if exists(select 1 from public.scores s join public.rounds r on r.id=s.round_id where s.id=sid and r.result_announced) then raise exception 'round_locked' using errcode='P0001';end if;if tg_op='DELETE' then return old;else return new;end if;end$$;
create trigger score_details_locked_guard before update or delete on public.score_details for each row execute function public.reject_locked_detail_change();

create view public.published_winners with(security_invoker=true) as select w.id,w.event_id,w.position,w.published_at,e.event_name,e.event_code,e.point_format,t.team_name,t.team_code from public.winner_announcements w join public.events e on e.id=w.event_id join public.teams t on t.id=w.team_id where w.published=true;
