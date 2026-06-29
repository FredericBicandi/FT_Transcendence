begin;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username varchar(32) unique not null,
  picture_url text,
  level int4 not null default 0,
  current_xp int4 not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.matches (
  id uuid primary key,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  duration_seconds int4 not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.played_matches (
  id bigserial primary key,
  match_id uuid not null references public.matches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  score int4 not null default 0,
  kills int4 not null default 0,
  deaths int4 not null default 0,
  time_played interval not null default interval '0 seconds',
  created_at timestamptz not null default now()
);

-- Add columns introduced after an earlier schema was deployed.
alter table public.profiles
  add column if not exists id uuid,
  add column if not exists username varchar(32),
  add column if not exists picture_url text,
  add column if not exists level int4 default 0,
  add column if not exists current_xp int4 default 0,
  add column if not exists created_at timestamptz default now(),
  add column if not exists updated_at timestamptz default now();

alter table public.matches
  add column if not exists id uuid,
  add column if not exists started_at timestamptz default now(),
  add column if not exists ended_at timestamptz,
  add column if not exists duration_seconds int4 default 0,
  add column if not exists created_at timestamptz default now();

alter table public.played_matches
  add column if not exists id bigserial,
  add column if not exists match_id uuid,
  add column if not exists user_id uuid,
  add column if not exists score int4 default 0,
  add column if not exists kills int4 default 0,
  add column if not exists deaths int4 default 0,
  add column if not exists time_played interval default interval '0 seconds',
  add column if not exists created_at timestamptz default now();

-- Keep application defaults consistent for future rows without rewriting
-- existing progression.
alter table public.profiles
  alter column level set default 0,
  alter column current_xp set default 0,
  alter column created_at set default now(),
  alter column updated_at set default now();

alter table public.matches
  alter column started_at set default now(),
  alter column duration_seconds set default 0,
  alter column created_at set default now();

alter table public.played_matches
  alter column score set default 0,
  alter column kills set default 0,
  alter column deaths set default 0,
  alter column time_played set default interval '0 seconds',
  alter column created_at set default now();

-- Named constraints are added only once. NOT VALID preserves legacy rows while
-- still enforcing each rule for every new or changed row.
do $migration$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_username_format_check'
  ) then
    alter table public.profiles
      add constraint profiles_username_format_check
      check (username ~ '^[a-z]{1,12}$') not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_avatar_check'
  ) then
    alter table public.profiles
      add constraint profiles_avatar_check
      check (
        picture_url is null
        or (
          octet_length(picture_url) <= 1400000
          and (
            picture_url like 'https://%'
            or picture_url like 'data:image/png;base64,%'
            or picture_url like 'data:image/jpeg;base64,%'
            or picture_url like 'data:image/gif;base64,%'
            or picture_url like 'data:image/webp;base64,%'
          )
        )
      ) not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_progress_check'
  ) then
    alter table public.profiles
      add constraint profiles_progress_check
      check (
        current_xp between 0 and 1000000
        and level between 0 and 10000
      ) not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.matches'::regclass
      and conname = 'matches_duration_check'
  ) then
    alter table public.matches
      add constraint matches_duration_check
      check (duration_seconds between 0 and 300) not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.matches'::regclass
      and conname = 'matches_timestamps_check'
  ) then
    alter table public.matches
      add constraint matches_timestamps_check
      check (ended_at is null or ended_at >= started_at) not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.played_matches'::regclass
      and conname = 'played_matches_statistics_check'
  ) then
    alter table public.played_matches
      add constraint played_matches_statistics_check
      check (
        score between 0 and 1000000
        and kills between 0 and 1000
        and deaths between 0 and 1000
        and time_played between interval '0 seconds' and interval '5 minutes'
      ) not valid;
  end if;

end
$migration$;

-- These indexes are safe to run repeatedly. The case-insensitive username
-- index closes the Foo/foo uniqueness gap in the original schema.
create unique index if not exists profiles_username_case_insensitive_unique
  on public.profiles (lower(username));

create unique index if not exists played_matches_user_match_unique
  on public.played_matches (user_id, match_id);

create index if not exists idx_played_matches_user_id
  on public.played_matches (user_id);

create index if not exists idx_played_matches_match_id
  on public.played_matches (match_id);

create index if not exists idx_profiles_username
  on public.profiles (username);

alter table public.profiles enable row level security;
alter table public.matches enable row level security;
alter table public.played_matches enable row level security;

drop policy if exists profiles_select_all on public.profiles;
drop policy if exists profiles_insert_own on public.profiles;
drop policy if exists profiles_update_own on public.profiles;
drop policy if exists matches_insert_anyone on public.matches;
drop policy if exists played_matches_select_own on public.played_matches;
drop policy if exists played_matches_insert_own on public.played_matches;

create policy profiles_select_all
on public.profiles
for select
to anon, authenticated
using (true);

create policy played_matches_select_own
on public.played_matches
for select
to authenticated
using ((select auth.uid()) = user_id);

-- Browser roles are read-only. Validated Next.js routes and the authoritative
-- .NET server use a server-only service-role key for database mutations.
revoke insert, update, delete
on public.profiles
from anon, authenticated;

revoke insert, update, delete
on public.matches
from anon, authenticated;

revoke insert, update, delete
on public.played_matches
from anon, authenticated;

grant select on public.profiles to anon, authenticated;
grant select on public.played_matches to authenticated;

grant select, insert, update, delete
on public.profiles, public.matches, public.played_matches
to service_role;

grant usage, select
on sequence public.played_matches_id_seq
to service_role;

commit;
