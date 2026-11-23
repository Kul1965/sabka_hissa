-- SABKA HISSA: secure company cloud + member login mapping
-- Run once in the NEW SABKA-HISSA-NEW Supabase project SQL Editor.
-- Passwords are NEVER stored in these tables. Supabase Auth stores password hashes.

create table if not exists public.company_state (
  id text primary key check (id = 'main'),
  data jsonb not null default '{}'::jsonb,
  updated_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  constraint company_state_data_object check (jsonb_typeof(data) = 'object')
);
alter table public.company_state enable row level security;
revoke all on public.company_state from anon;
grant select, insert, update on public.company_state to authenticated;

drop policy if exists "SABKA HISSA admin reads company data" on public.company_state;
create policy "SABKA HISSA admin reads company data"
on public.company_state for select to authenticated
using (lower(coalesce(auth.jwt()->>'email','')) = 'acharya.kp65@gmail.com');

drop policy if exists "SABKA HISSA admin creates company data" on public.company_state;
create policy "SABKA HISSA admin creates company data"
on public.company_state for insert to authenticated
with check (
  lower(coalesce(auth.jwt()->>'email','')) = 'acharya.kp65@gmail.com'
  and updated_by = auth.uid()
);

drop policy if exists "SABKA HISSA admin updates company data" on public.company_state;
create policy "SABKA HISSA admin updates company data"
on public.company_state for update to authenticated
using (lower(coalesce(auth.jwt()->>'email','')) = 'acharya.kp65@gmail.com')
with check (
  lower(coalesce(auth.jwt()->>'email','')) = 'acharya.kp65@gmail.com'
  and updated_by = auth.uid()
);

-- Link a Supabase Auth login to one existing SABKA HISSA member.
create table if not exists public.member_login_accounts (
  member_id text primary key,
  auth_user_id uuid unique not null references auth.users(id) on delete cascade,
  member_name text not null,
  username text unique,
  login_email text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id)
);
alter table public.member_login_accounts enable row level security;
-- Edge Functions use the service_role client to create and link member logins.
-- RLS is bypassed by service_role, but SQL table privileges are still required.
grant all privileges on table public.member_login_accounts to service_role;

revoke all on public.member_login_accounts from anon;
grant select, insert, update, delete on public.member_login_accounts to authenticated;

drop policy if exists "Admin manages member login accounts" on public.member_login_accounts;
create policy "Admin manages member login accounts"
on public.member_login_accounts for all to authenticated
using (lower(coalesce(auth.jwt()->>'email','')) = 'acharya.kp65@gmail.com')
with check (
  lower(coalesce(auth.jwt()->>'email','')) = 'acharya.kp65@gmail.com'
  and created_by = auth.uid()
);

drop policy if exists "Member reads own login mapping" on public.member_login_accounts;
create policy "Member reads own login mapping"
on public.member_login_accounts for select to authenticated
using (auth.uid() = auth_user_id and is_active = true);

-- Private member portal data: one row per member. Only that member and Admin can read it.
create table if not exists public.member_portal_data (
  member_id text primary key references public.member_login_accounts(member_id) on delete cascade,
  member_data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  constraint member_portal_data_object check (jsonb_typeof(member_data) = 'object')
);
alter table public.member_portal_data enable row level security;
grant all privileges on table public.member_portal_data to service_role;

revoke all on public.member_portal_data from anon;
grant select, insert, update, delete on public.member_portal_data to authenticated;

drop policy if exists "Admin manages member portal data" on public.member_portal_data;
create policy "Admin manages member portal data"
on public.member_portal_data for all to authenticated
using (lower(coalesce(auth.jwt()->>'email','')) = 'acharya.kp65@gmail.com')
with check (lower(coalesce(auth.jwt()->>'email','')) = 'acharya.kp65@gmail.com');

drop policy if exists "Member reads own portal data" on public.member_portal_data;
create policy "Member reads own portal data"
on public.member_portal_data for select to authenticated
using (
  exists (
    select 1 from public.member_login_accounts a
    where a.member_id = member_portal_data.member_id
      and a.auth_user_id = auth.uid()
      and a.is_active = true
  )
);

create or replace function public.touch_company_state_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;
drop trigger if exists company_state_updated_at on public.company_state;
create trigger company_state_updated_at before update on public.company_state
for each row execute function public.touch_company_state_updated_at();

create or replace function public.touch_member_portal_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;
drop trigger if exists member_portal_data_updated_at on public.member_portal_data;
create trigger member_portal_data_updated_at before update on public.member_portal_data
for each row execute function public.touch_member_portal_updated_at();


-- Safe migration for existing installations: keep old records and add username login support.
alter table public.member_login_accounts
  add column if not exists username text;
create unique index if not exists member_login_accounts_username_unique
  on public.member_login_accounts (lower(username))
  where username is not null;
