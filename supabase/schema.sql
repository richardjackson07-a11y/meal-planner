-- Jackson Family Meal Planner — Supabase schema
-- Run this in the Supabase dashboard under SQL Editor → New query.
--
-- Two parts:
--   1. the keep-alive heartbeat the GitHub Action writes to
--   2. the app's own tables, which keep every week forever so you get
--      real history rather than just "this week"

-- ============================================================
-- 1. KEEP-ALIVE
-- ============================================================

create table if not exists public.heartbeat (
  id         int primary key default 1,
  last_ping  timestamptz not null default now(),
  pings      bigint      not null default 0,
  constraint heartbeat_single_row check (id = 1)
);

insert into public.heartbeat (id) values (1) on conflict (id) do nothing;

alter table public.heartbeat enable row level security;
-- No policies on purpose: nothing can touch this table directly. The function
-- below is SECURITY DEFINER, so it is the only way in.

create or replace function public.keepalive()
returns timestamptz
language sql
security definer
set search_path = public
as $$
  update public.heartbeat
     set last_ping = now(),
         pings     = pings + 1
   where id = 1
  returning last_ping;
$$;

revoke all on function public.keepalive() from public;
grant execute on function public.keepalive() to anon, authenticated;


-- ============================================================
-- 2. APP TABLES
-- ============================================================

create extension if not exists "pgcrypto";

create table if not exists public.households (
  id         uuid primary key default gen_random_uuid(),
  name       text not null default 'Jackson Family',
  created_at timestamptz not null default now()
);

-- Who is allowed into which household. One row per person per household.
create table if not exists public.household_members (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id      uuid not null references auth.users(id)        on delete cascade,
  joined_at    timestamptz not null default now(),
  primary key (household_id, user_id)
);

create table if not exists public.recipes (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name         text not null,
  emoji        text,
  servings     smallint not null default 4,
  time_text    text,
  tags         text[] not null default '{}',
  ingredients  jsonb  not null default '[]',
  notes        text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz            -- soft delete, so a sync cannot resurrect it
);
create index if not exists recipes_household_idx on public.recipes (household_id) where deleted_at is null;
create index if not exists recipes_tags_idx      on public.recipes using gin (tags);

-- One row per planned dinner. Keeping week_start as a real date means every
-- week you have ever planned stays queryable.
create table if not exists public.plan_days (
  household_id uuid     not null references public.households(id) on delete cascade,
  week_start   date     not null,
  day_index    smallint not null check (day_index between 0 and 6),
  recipe_id    uuid references public.recipes(id) on delete set null,
  note_text    text,                 -- for "Leftovers" / "Eat out" nights
  emoji        text,
  servings     smallint,
  updated_at   timestamptz not null default now(),
  primary key (household_id, week_start, day_index)
);
create index if not exists plan_days_week_idx on public.plan_days (household_id, week_start desc);

create table if not exists public.extras (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  week_start   date not null,
  name         text not null,
  aisle        text,
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index if not exists extras_week_idx on public.extras (household_id, week_start) where deleted_at is null;

create table if not exists public.item_checks (
  household_id uuid not null references public.households(id) on delete cascade,
  week_start   date not null,
  item_key     text not null,
  checked      boolean not null default true,
  updated_at   timestamptz not null default now(),
  primary key (household_id, week_start, item_key)
);


-- ============================================================
-- 3. ROW LEVEL SECURITY
--    Every table is readable and writable only by members of that household.
-- ============================================================

create or replace function public.is_member(h uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.household_members m
     where m.household_id = h and m.user_id = auth.uid()
  );
$$;

alter table public.households        enable row level security;
alter table public.household_members enable row level security;
alter table public.recipes           enable row level security;
alter table public.plan_days         enable row level security;
alter table public.extras            enable row level security;
alter table public.item_checks       enable row level security;

drop policy if exists households_read on public.households;
create policy households_read on public.households
  for select using (public.is_member(id));

drop policy if exists members_read on public.household_members;
create policy members_read on public.household_members
  for select using (user_id = auth.uid() or public.is_member(household_id));

do $$
declare t text;
begin
  foreach t in array array['recipes','plan_days','extras','item_checks'] loop
    execute format('drop policy if exists %I_all on public.%I', t, t);
    execute format(
      'create policy %I_all on public.%I for all
         using (public.is_member(household_id))
         with check (public.is_member(household_id))', t, t);
  end loop;
end $$;


-- ============================================================
-- 4. TOUCH updated_at ON EVERY WRITE
-- ============================================================

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['recipes','plan_days','extras','item_checks'] loop
    execute format('drop trigger if exists %I_touch on public.%I', t, t);
    execute format(
      'create trigger %I_touch before update on public.%I
         for each row execute function public.touch_updated_at()', t, t);
  end loop;
end $$;


-- ============================================================
-- 5. LIVE UPDATES — so her phone changes appear on yours instantly
-- ============================================================

-- "already member of publication" is fine on a re-run, so swallow it.
do $$
declare t text;
begin
  foreach t in array array['recipes','plan_days','extras','item_checks'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then
      raise notice 'realtime already enabled for %', t;
    end;
  end loop;
end $$;


-- ============================================================
-- 6. HISTORY HELPERS — what the move to Postgres actually buys you
-- ============================================================

-- How often each recipe has been cooked, and when it last came up.
create or replace view public.recipe_history as
  select r.household_id,
         r.id, r.name, r.tags,
         count(p.*)          as times_cooked,
         max(p.week_start)   as last_cooked
    from public.recipes r
    left join public.plan_days p on p.recipe_id = r.id
   where r.deleted_at is null
   group by r.household_id, r.id, r.name, r.tags;

-- Every week you have ever planned, newest first.
create or replace view public.week_history as
  select household_id,
         week_start,
         count(*) filter (where recipe_id is not null or note_text is not null) as nights_planned
    from public.plan_days
   group by household_id, week_start
   order by week_start desc;
