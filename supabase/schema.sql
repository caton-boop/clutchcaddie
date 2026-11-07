-- Clutch Caddie database for Supabase (Postgres): profiles, leaderboards and the Caddy Cup.
-- Run this once in the Supabase dashboard: SQL Editor > New query > paste everything > Run.
-- Safe to run again: it only adds what is missing and replaces the functions.
--
-- How it works
--   * players: one row per profile. A player picks a name; the server makes a player code
--     (CC-XXXX-XXXX-XXXX-XXXX) that signs them in on any device. Only a SHA-256 hash of the code
--     is stored, so the database never holds a usable code.
--   * scores: one row per posted ranked result. Each row belongs to a board:
--       daily:YYYY-MM-DD    score = strokes on the hole (lower is better)
--       weekly:YYYY-MM-DD   the Monday the week started; score = total to par
--       monthly:YYYY-MM     score = total to par
--   * Caddy Cup points come from where you finished on each board (see board_results below).
--     The weekly 18 is worth three times a daily, like a major.
--   * The browser never touches the tables directly. Row level security is on with no policies;
--     the public key can only call the functions at the bottom.

-- ---------- tables ----------
create table if not exists public.players (
  id          uuid        primary key,
  name        text        not null,
  code_hash   text        not null unique,
  created_at  timestamptz not null default now()
);
create unique index if not exists players_name_lower_idx on public.players (lower(name));

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
create index if not exists scores_player_idx on public.scores (player_id);

create table if not exists public.blocked_words (w text primary key);
insert into public.blocked_words (w) values
  ('fuck'),('shit'),('cunt'),('nigg'),('fagg'),('bitch'),('pussy'),('whore'),('slut'),
  ('rapist'),('nazi'),('hitler'),('kike'),('retard'),('twat'),('wank'),('cocksuck'),('dickhead')
on conflict do nothing;

-- Caddy Cup seasons. Change the dates or add the next season with a simple insert.
create table if not exists public.seasons (
  id      serial primary key,
  name    text not null,
  starts  date not null,
  ends    date not null
);
insert into public.seasons (name, starts, ends)
select 'Season 1', date '2026-11-01', date '2027-03-31'
where not exists (select 1 from public.seasons);

alter table public.players       enable row level security;
alter table public.scores        enable row level security;
alter table public.blocked_words enable row level security;
alter table public.seasons       enable row level security;
revoke all on table public.players, public.scores, public.blocked_words, public.seasons from anon, authenticated;

-- ---------- helpers ----------
-- Today's date in US Eastern time (the game resets at midnight ET).
create or replace function public.et_today() returns date
language sql stable as $$ select (now() at time zone 'America/New_York')::date $$;

create or replace function public.code_hash(p_code text) returns text
language sql immutable as $$ select encode(sha256(convert_to(p_code, 'UTF8')), 'hex') $$;

-- Validates a display name and returns it cleaned up.
create or replace function public.check_name(p_name text) returns text
language plpgsql stable set search_path = public as $$
declare
  nm  text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  ltr text;
begin
  if nm !~ '^[A-Za-z0-9 ._''-]{2,16}$' then raise exception 'bad name'; end if;
  ltr := regexp_replace(translate(lower(nm), '0134578', 'oieastb'), '[^a-z]', '', 'g');
  if exists (select 1 from blocked_words b where position(b.w in ltr) > 0) then
    raise exception 'name not allowed';
  end if;
  return nm;
end $$;

-- Caddy Cup points for one finish. Daily: 10 for posting, up to 90 more by how much of the field you
-- beat, plus 50/30/20 for the top three. Weekly or monthly 18: three times that.
create or replace function public.cup_points(p_kind text, p_rank bigint, p_field bigint) returns integer
language sql immutable as $$
  select (case when p_kind = 'daily' then 1 else 3 end) * (
           10
         + round(90 * case when p_field > 1 then (p_field - p_rank)::numeric / (p_field - 1) else 1 end)::int
         + case p_rank when 1 then 50 when 2 then 30 when 3 then 20 else 0 end)
$$;

-- Every posted result with its place on its board and its Caddy Cup points.
create or replace view public.board_results as
select s.board, s.player_id, s.score, s.rating, s.detail, s.created_at,
       split_part(s.board, ':', 1) as kind,
       case when s.board like 'monthly:%'
            then to_date(split_part(s.board, ':', 2) || '-01', 'YYYY-MM-DD')
            else to_date(split_part(s.board, ':', 2), 'YYYY-MM-DD') end as bdate,
       rank()   over (partition by s.board order by s.score asc, s.rating desc) as rk,
       count(*) over (partition by s.board)                                    as field,
       public.cup_points(split_part(s.board, ':', 1),
                         rank() over (partition by s.board order by s.score asc, s.rating desc),
                         count(*) over (partition by s.board))                 as points
from public.scores s;
revoke all on table public.board_results from anon, authenticated;

-- ---------- functions the game calls ----------

-- Create a profile. p_player is the random ID the device already uses, so any scores it posted
-- before making a profile come along. Returns the player code once; it cannot be shown again.
create or replace function public.create_player(p_player uuid, p_name text) returns json
language plpgsql security definer set search_path = public as $$
declare
  nm   text := check_name(p_name);
  h    text := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  code text;
begin
  if exists (select 1 from players where id = p_player) then raise exception 'profile exists'; end if;
  if exists (select 1 from players where lower(name) = lower(nm)) then raise exception 'name taken'; end if;
  -- 16 random hex characters (64 bits): characters 1-12 and 33-36 avoid the UUID version digits.
  code := 'CC-' || upper(substr(h, 1, 4) || '-' || substr(h, 5, 4) || '-' || substr(h, 9, 4) || '-' || substr(h, 33, 4));
  insert into players (id, name, code_hash) values (p_player, nm, code_hash(code));
  update scores set name = nm where player_id = p_player;
  return json_build_object('player_id', p_player, 'name', nm, 'code', code);
end $$;

-- Sign in on any device with a player code.
create or replace function public.login_with_code(p_code text) returns json
language plpgsql security definer set search_path = public as $$
declare
  c  text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  pl players%rowtype;
begin
  if c like 'CC%' then c := substr(c, 3); end if;
  if c !~ '^[0-9A-F]{16}$' then raise exception 'code not found'; end if;
  c := 'CC-' || substr(c, 1, 4) || '-' || substr(c, 5, 4) || '-' || substr(c, 9, 4) || '-' || substr(c, 13, 4);
  select * into pl from players where code_hash = code_hash(c);
  if not found then raise exception 'code not found'; end if;
  return json_build_object('player_id', pl.id, 'name', pl.name, 'code', c);
end $$;

-- Post a ranked result. Needs a profile; the name always comes from the profile.
create or replace function public.submit_score(
  p_board  text,
  p_player uuid,
  p_name   text,
  p_score  integer,
  p_rating integer,
  p_detail jsonb default null
) returns json
language plpgsql security definer set search_path = public as $$
declare
  d   date := et_today();
  wk  date := d - (extract(isodow from d)::int - 1);
  nm  text;
begin
  select name into nm from players where id = p_player;
  if nm is null then raise exception 'no profile'; end if;

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

  return (select json_build_object('ok', true, 'rank', rk, 'field', field, 'points', points)
          from board_results where board = p_board and player_id = p_player);
end $$;

-- One board: the top N plus the caller's own row.
create or replace function public.get_board(
  p_board  text,
  p_player uuid,
  p_limit  integer default 50
) returns table (rank bigint, name text, score integer, rating integer, is_you boolean, total bigint, points integer)
language sql stable security definer set search_path = public as $$
  select r.rk, coalesce(p.name, s.name), r.score, r.rating, r.player_id = p_player, r.field, r.points
  from board_results r
  join scores s on s.board = r.board and s.player_id = r.player_id
  left join players p on p.id = r.player_id
  where r.board = p_board
    and (r.rk <= least(greatest(p_limit, 1), 100) or r.player_id = p_player)
  order by r.rk, r.created_at;
$$;

-- Caddy Cup standings for the current season (profiles only).
create or replace function public.get_caddy_cup(p_player uuid, p_limit integer default 100)
returns table (rank bigint, name text, points bigint, events bigint, wins bigint, top10 bigint,
               is_you boolean, total bigint, season text, season_ends date)
language sql stable security definer set search_path = public as $$
  with s as (
    select * from seasons where et_today() between starts and ends order by starts desc limit 1
  ), agg as (
    select r.player_id, sum(r.points) as pts, count(*) as ev,
           count(*) filter (where r.rk = 1) as wins, count(*) filter (where r.rk <= 10) as t10
    from board_results r, s
    where r.bdate between s.starts and s.ends
    group by r.player_id
  ), ranked as (
    select a.*, p.name, rank() over (order by a.pts desc) as rk, count(*) over () as tot
    from agg a join players p on p.id = a.player_id
  )
  select ranked.rk, ranked.name, ranked.pts, ranked.ev, ranked.wins, ranked.t10,
         ranked.player_id = p_player, ranked.tot, (select name from s), (select ends from s)
  from ranked
  where ranked.rk <= least(greatest(p_limit, 1), 200) or ranked.player_id = p_player
  order by ranked.rk, ranked.name;
$$;

-- Everything the profile page shows.
create or replace function public.get_player_stats(p_player uuid) returns json
language plpgsql stable security definer set search_path = public as $$
declare
  pl  players%rowtype;
  cup record;
begin
  select * into pl from players where id = p_player;
  if not found then raise exception 'no profile'; end if;
  select * into cup from get_caddy_cup(p_player, 1) c where c.is_you;
  return json_build_object(
    'name', pl.name,
    'since', pl.created_at,
    'season', (select name from seasons where et_today() between starts and ends order by starts desc limit 1),
    'cup_rank', cup.rank, 'cup_points', coalesce(cup.points, 0), 'cup_field', cup.total,
    'dailies', (select count(*) from board_results where player_id = p_player and kind = 'daily'),
    'weeklies', (select count(*) from board_results where player_id = p_player and kind <> 'daily'),
    'wins', (select count(*) from board_results where player_id = p_player and rk = 1),
    'top10', (select count(*) from board_results where player_id = p_player and rk <= 10),
    'daily_vs_par', (select round(avg(score - (detail->>'par')::int), 2) from board_results
                     where player_id = p_player and kind = 'daily' and detail ? 'par'),
    'best_weekly', (select min(score) from board_results where player_id = p_player and kind <> 'daily'),
    'beat_pro', (select count(*) from board_results where player_id = p_player and (detail->>'beat')::boolean),
    'recent', coalesce((select json_agg(x) from (
        select board, kind, bdate, score, rk as rank, field, points, detail->>'par' as par
        from board_results where player_id = p_player order by bdate desc, created_at desc limit 14) x), '[]'::json)
  );
end $$;

-- ---------- permissions ----------
revoke all on function public.create_player(uuid, text) from public;
revoke all on function public.login_with_code(text) from public;
revoke all on function public.submit_score(text, uuid, text, integer, integer, jsonb) from public;
revoke all on function public.get_board(text, uuid, integer) from public;
revoke all on function public.get_caddy_cup(uuid, integer) from public;
revoke all on function public.get_player_stats(uuid) from public;
grant execute on function public.create_player(uuid, text) to anon, authenticated;
grant execute on function public.login_with_code(text) to anon, authenticated;
grant execute on function public.submit_score(text, uuid, text, integer, integer, jsonb) to anon, authenticated;
grant execute on function public.get_board(text, uuid, integer) to anon, authenticated;
grant execute on function public.get_caddy_cup(uuid, integer) to anon, authenticated;
grant execute on function public.get_player_stats(uuid) to anon, authenticated;

-- ---------- handy admin queries (run by hand) ----------
--   Remove a score:      delete from public.scores where board = 'daily:2026-11-06' and name = 'SomeName';
--   Rename a player:     update public.players set name = 'NewName' where name = 'OldName';
--   Block a word:        insert into public.blocked_words (w) values ('word');
--   Start a new season:  insert into public.seasons (name, starts, ends) values ('Season 2', '2027-04-01', '2027-08-31');
