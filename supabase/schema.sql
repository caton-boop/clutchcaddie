-- Clutch Caddie leaderboard schema for Supabase (Postgres).
-- Run this once in the Supabase dashboard: SQL Editor > New query > paste > Run.
--
-- How it works
--   * One table, scores, holds every posted score. Each row belongs to a board:
--       daily:YYYY-MM-DD    (score = strokes on the hole, lower is better)
--       weekly:YYYY-MM-DD   (Monday the week started; score = total to par)
--       monthly:YYYY-MM     (score = total to par)
--   * The browser never touches the table directly. Row level security is on with no policies,
--     so the public key can only call the two functions below.
--   * submit_score validates the board, score range and name, and keeps the first score per
--     player per board (later posts are ignored).
--   * get_board returns the top N plus the caller's own row, with ranks.

create table if not exists public.scores (
  id          bigint generated always as identity primary key,
  board       text        not null,
  player_id   uuid        not null,
  name        text        not null,
  score       integer     not null,
  rating      integer     not null default 0,
  detail      jsonb,
  created_at  timestamptz not null default now(),
  unique (board, player_id)
);

create index if not exists scores_board_rank_idx on public.scores (board, score, rating desc, created_at);

alter table public.scores enable row level security;
revoke all on table public.scores from anon, authenticated;

-- Words that may not appear in names (matched after lowercasing and removing non-letters).
create table if not exists public.blocked_words (w text primary key);
alter table public.blocked_words enable row level security;
revoke all on table public.blocked_words from anon, authenticated;
insert into public.blocked_words (w) values
  ('fuck'),('shit'),('cunt'),('nigg'),('fagg'),('bitch'),('pussy'),('whore'),('slut'),
  ('rapist'),('nazi'),('hitler'),('kike'),('retard'),('twat'),('wank'),('cocksuck'),('dickhead')
on conflict do nothing;

-- Today's date in US Eastern time (the game resets at midnight ET).
create or replace function public.et_today() returns date
language sql stable as $$ select (now() at time zone 'America/New_York')::date $$;

create or replace function public.submit_score(
  p_board  text,
  p_player uuid,
  p_name   text,
  p_score  integer,
  p_rating integer,
  p_detail jsonb default null
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  d   date := et_today();
  wk  date := d - (extract(isodow from d)::int - 1);   -- Monday of this week
  nm  text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  ltr text;
begin
  if nm !~ '^[A-Za-z0-9 ._''-]{2,16}$' then
    raise exception 'bad name';
  end if;
  ltr := regexp_replace(translate(lower(nm), '0134578', 'oieastb'), '[^a-z]', '', 'g');
  if exists (select 1 from blocked_words b where position(b.w in ltr) > 0) then
    raise exception 'name not allowed';
  end if;

  if p_board in ('daily:' || to_char(d, 'YYYY-MM-DD'), 'daily:' || to_char(d - 1, 'YYYY-MM-DD')) then
    if p_score not between 1 and 15 then raise exception 'bad score'; end if;
  elsif p_board in ('weekly:' || to_char(wk, 'YYYY-MM-DD'), 'weekly:' || to_char(wk - 7, 'YYYY-MM-DD')) then
    if p_score not between -40 and 60 then raise exception 'bad score'; end if;
  elsif p_board in ('monthly:' || to_char(d, 'YYYY-MM'), 'monthly:' || to_char((date_trunc('month', d) - interval '1 day')::date, 'YYYY-MM')) then
    if p_score not between -40 and 60 then raise exception 'bad score'; end if;
  else
    raise exception 'bad board';
  end if;

  if p_rating not between 0 and 100 then raise exception 'bad rating'; end if;

  insert into scores (board, player_id, name, score, rating, detail)
  values (p_board, p_player, nm, p_score, p_rating, p_detail)
  on conflict (board, player_id) do nothing;

  return json_build_object('ok', true);
end;
$$;

create or replace function public.get_board(
  p_board  text,
  p_player uuid,
  p_limit  integer default 50
) returns table (rank bigint, name text, score integer, rating integer, is_you boolean, total bigint)
language sql
stable
security definer
set search_path = public
as $$
  with r as (
    select s.name, s.score, s.rating, s.player_id, s.created_at,
           rank()   over (order by s.score asc, s.rating desc) as rk,
           count(*) over ()                                    as tot
    from scores s
    where s.board = p_board
  )
  select rk, r.name, r.score, r.rating, r.player_id = p_player, tot
  from r
  where rk <= least(greatest(p_limit, 1), 100) or r.player_id = p_player
  order by rk, r.created_at;
$$;

revoke all on function public.submit_score(text, uuid, text, integer, integer, jsonb) from public;
revoke all on function public.get_board(text, uuid, integer) from public;
grant execute on function public.submit_score(text, uuid, text, integer, integer, jsonb) to anon, authenticated;
grant execute on function public.get_board(text, uuid, integer) to anon, authenticated;

-- Moderation helpers (run by hand in the SQL editor):
--   delete from public.scores where board = 'daily:2026-11-06' and name = 'SomeName';
--   insert into public.blocked_words (w) values ('newword');
