create table if not exists public.progress (
  level integer not null,
  xp_required integer not null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint progress_pkey primary key (level),
  constraint progress_level_non_negative check (level >= 0),
  constraint progress_xp_required_positive check (xp_required > 0)
) tablespace pg_default;

alter table public.progress enable row level security;

drop policy if exists "Progress is readable by everyone" on public.progress;

create policy "Progress is readable by everyone"
  on public.progress
  for select
  using (true);

insert into public.progress (level, xp_required)
values
  (0, 100),
  (1, 100),
  (2, 150),
  (3, 225),
  (4, 325),
  (5, 450),
  (6, 600),
  (7, 775),
  (8, 975),
  (9, 1200),
  (10, 1450)
on conflict (level) do update
set
  xp_required = excluded.xp_required,
  updated_at = now();
