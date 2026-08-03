-- Cadence — close the self-service "pro" hole.
--
-- The initial migration enabled RLS on public.profiles and added an UPDATE
-- policy named "(limited)", but RLS gates ROWS, not COLUMNS. Supabase grants
-- anon/authenticated full DML on public tables by default, and the initial
-- migration only revoked EXECUTE on functions, never UPDATE on the table.
--
-- Net effect before this migration: any signed-in user could PATCH their own
-- profiles row with the shipped publishable key and their own valid JWT --
--   {"plan":"pro","monthly_seconds_used":0}
-- -- granting themselves Pro with no Stripe involvement, and resetting the
-- free-tier meter to zero on demand.
--
-- Fix: take the table-level grant away and hand back only the harmless column.
-- The existing row policy stays as the row gate. The Worker is unaffected --
-- it uses the service_role key, which bypasses RLS and these grants.

revoke update on public.profiles from anon, authenticated;

-- Users may correct their own email. Nothing else.
grant update (email) on public.profiles to authenticated;

-- Defence in depth: even if a future migration re-grants the table, refuse
-- privilege escalation from any caller that is not the service role.
create or replace function public.guard_profile_privileged_columns()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  jwt_role text := coalesce(
    current_setting('request.jwt.claims', true)::json ->> 'role',
    ''
  );
begin
  if jwt_role = 'service_role' then
    return new;
  end if;

  if new.plan is distinct from old.plan then
    raise exception 'plan may only be changed by the billing service';
  end if;

  if new.monthly_seconds_used is distinct from old.monthly_seconds_used then
    raise exception 'usage may only be changed by the billing service';
  end if;

  if new.quota_reset_at is distinct from old.quota_reset_at then
    raise exception 'quota window may only be changed by the billing service';
  end if;

  if new.stripe_customer_id is distinct from old.stripe_customer_id then
    raise exception 'stripe customer id may only be changed by the billing service';
  end if;

  return new;
end;
$$;

revoke execute on function public.guard_profile_privileged_columns() from public, anon, authenticated;

drop trigger if exists guard_profile_privileged_columns on public.profiles;
create trigger guard_profile_privileged_columns
  before update on public.profiles
  for each row execute function public.guard_profile_privileged_columns();
