-- Cadence backend schema (Supabase Postgres)
-- Run: supabase db push   OR paste into Supabase SQL editor

-- ── Profiles (extends auth.users) ───────────────────────────────────────────

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  plan text not null default 'free' check (plan in ('free', 'pro')),
  monthly_seconds_used numeric not null default 0,
  quota_reset_at timestamptz not null default (date_trunc('month', now()) + interval '1 month'),
  stripe_customer_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Users read own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Users update own profile (limited)"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Service role (Worker) bypasses RLS when using service_role key.

-- Auto-create profile on signup (including anonymous)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── Quota helpers ───────────────────────────────────────────────────────────

create or replace function public.reset_quota_if_needed(p_user_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update public.profiles
  set monthly_seconds_used = 0,
      quota_reset_at = date_trunc('month', now()) + interval '1 month',
      updated_at = now()
  where id = p_user_id
    and quota_reset_at <= now();
end;
$$;

create or replace function public.increment_transcription_seconds(
  p_user_id uuid,
  p_seconds numeric
)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  perform public.reset_quota_if_needed(p_user_id);
  update public.profiles
  set monthly_seconds_used = monthly_seconds_used + greatest(p_seconds, 0),
      updated_at = now()
  where id = p_user_id;
end;
$$;

-- Only the Worker (service_role) should call RPCs. Lock down public/anon/auth.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.reset_quota_if_needed(uuid) from public, anon, authenticated;
revoke execute on function public.increment_transcription_seconds(uuid, numeric) from public, anon, authenticated;

grant execute on function public.reset_quota_if_needed(uuid) to service_role;
grant execute on function public.increment_transcription_seconds(uuid, numeric) to service_role;

-- Free tier: 10,800 seconds/month ≈ 3 hours of audio
comment on table public.profiles is 'Per-user plan and transcription quota for Cadence Cloud';
