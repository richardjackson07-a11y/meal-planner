-- Jackson Family Meal Planner — household setup functions
-- Run this in the Supabase SQL Editor AFTER schema.sql.
--
-- These let the app create the household and invite your wife from inside the
-- app, instead of you hand-editing tables. Both are SECURITY DEFINER because
-- they need to touch auth.users and insert the very membership row that the
-- RLS policies check.

-- Create a household and make the caller its first member.
-- Returns the household id. If the caller is already in one, returns that.
create or replace function public.create_household(household_name text default 'Jackson Family')
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  existing uuid;
  new_id   uuid;
begin
  if auth.uid() is null then
    raise exception 'must be signed in';
  end if;

  select household_id into existing
    from public.household_members
   where user_id = auth.uid()
   limit 1;

  if existing is not null then
    return existing;
  end if;

  insert into public.households (name)
  values (coalesce(nullif(trim(household_name), ''), 'Jackson Family'))
  returning id into new_id;

  insert into public.household_members (household_id, user_id)
  values (new_id, auth.uid());

  return new_id;
end $$;

revoke all on function public.create_household(text) from public;
grant execute on function public.create_household(text) to authenticated;


-- Add someone to your household by email. They must have signed in once
-- already, so that an auth.users row exists for them.
create or replace function public.invite_to_household(invitee_email text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  my_household uuid;
  invitee      uuid;
begin
  if auth.uid() is null then
    raise exception 'must be signed in';
  end if;

  select household_id into my_household
    from public.household_members
   where user_id = auth.uid()
   limit 1;

  if my_household is null then
    raise exception 'you are not in a household yet';
  end if;

  select id into invitee
    from auth.users
   where lower(email) = lower(trim(invitee_email))
   limit 1;

  if invitee is null then
    return 'not_signed_up';
  end if;

  insert into public.household_members (household_id, user_id)
  values (my_household, invitee)
  on conflict do nothing;

  return 'added';
end $$;

revoke all on function public.invite_to_household(text) from public;
grant execute on function public.invite_to_household(text) to authenticated;


-- Which household am I in? Cheap lookup the app calls on sign-in.
create or replace function public.my_household()
returns uuid
language sql
security definer
stable
set search_path = public
as $$
  select household_id
    from public.household_members
   where user_id = auth.uid()
   limit 1;
$$;

revoke all on function public.my_household() from public;
grant execute on function public.my_household() to authenticated;
