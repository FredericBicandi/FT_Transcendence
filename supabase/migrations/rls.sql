begin;

alter table public.profiles enable row level security;
alter table public.matches enable row level security;
alter table public.played_matches enable row level security;

-- Recreate policies so this migration is safe to apply more than once.
drop policy if exists profiles_select_all on public.profiles;
drop policy if exists profiles_insert_own on public.profiles;
drop policy if exists profiles_update_own on public.profiles;
drop policy if exists matches_insert_anyone on public.matches;
drop policy if exists played_matches_select_own on public.played_matches;
drop policy if exists played_matches_insert_own on public.played_matches;

-- Profiles are public game identities. All mutations go through /api/profile.
create policy profiles_select_all
on public.profiles
for select
to anon, authenticated
using (true);

-- Match history remains private to its authenticated owner.
create policy played_matches_select_own
on public.played_matches
for select
to authenticated
using ((select auth.uid()) = user_id);

-- RLS policies do not replace SQL grants. Browser roles are read-only;
-- validated Next.js routes and the authoritative .NET server use service_role.
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
