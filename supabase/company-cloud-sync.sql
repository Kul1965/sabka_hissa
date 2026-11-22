-- SABKA HISSA: secure single-admin cloud data sync
-- Run this SQL once in the NEW SABKA-HISSA-NEW Supabase project.
-- Only the designated Admin email can read or change company records.
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

create or replace function public.touch_company_state_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
drop trigger if exists company_state_updated_at on public.company_state;
create trigger company_state_updated_at
before update on public.company_state
for each row execute function public.touch_company_state_updated_at();
