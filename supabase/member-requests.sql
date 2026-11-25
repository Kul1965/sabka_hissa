-- SABKA HISSA: Member withdrawal and salary application workflow
-- Run this migration in the Supabase SQL Editor for the SABKA HISSA project.
-- Existing company, investment, salary and member records are not changed.

create table if not exists public.member_requests (
  id uuid primary key default gen_random_uuid(),
  member_id text not null references public.member_login_accounts(member_id) on delete cascade,
  member_name text not null,
  request_type text not null check (request_type in ('withdrawal','salary')),
  requested_amount numeric(14,2) not null check (requested_amount > 0),
  approved_amount numeric(14,2),
  reason text not null default '',
  status text not null default 'pending' check (status in ('pending','approved','rejected','paid')),
  admin_note text not null default '',
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id),
  paid_at timestamptz,
  payment_entry_id text,
  constraint member_requests_approved_amount_valid
    check (approved_amount is null or (approved_amount > 0 and approved_amount <= requested_amount))
);

create index if not exists member_requests_member_created_idx
  on public.member_requests(member_id, created_at desc);
create index if not exists member_requests_status_created_idx
  on public.member_requests(status, created_at desc);

alter table public.member_requests enable row level security;
revoke all on public.member_requests from anon;
grant select, insert, update on public.member_requests to authenticated;
grant all privileges on public.member_requests to service_role;

drop policy if exists "Member reads own money requests" on public.member_requests;
create policy "Member reads own money requests"
on public.member_requests for select to authenticated
using (
  exists (
    select 1 from public.member_login_accounts a
    where a.member_id = member_requests.member_id
      and a.auth_user_id = auth.uid()
      and a.is_active = true
  )
);

drop policy if exists "Member submits own money requests" on public.member_requests;
create policy "Member submits own money requests"
on public.member_requests for insert to authenticated
with check (
  status = 'pending'
  and approved_amount is null
  and reviewed_at is null
  and reviewed_by is null
  and paid_at is null
  and payment_entry_id is null
  and exists (
    select 1 from public.member_login_accounts a
    where a.member_id = member_requests.member_id
      and a.auth_user_id = auth.uid()
      and a.is_active = true
      and a.member_name = member_requests.member_name
  )
);

drop policy if exists "Admin reviews money requests" on public.member_requests;
create policy "Admin reviews money requests"
on public.member_requests for select to authenticated
using (lower(coalesce(auth.jwt()->>'email','')) = 'acharya.kp65@gmail.com');

drop policy if exists "Admin updates money requests" on public.member_requests;
create policy "Admin updates money requests"
on public.member_requests for update to authenticated
using (lower(coalesce(auth.jwt()->>'email','')) = 'acharya.kp65@gmail.com')
with check (lower(coalesce(auth.jwt()->>'email','')) = 'acharya.kp65@gmail.com');

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'member_requests'
  ) then
    alter publication supabase_realtime add table public.member_requests;
  end if;
exception when undefined_object then
  null;
end $$;
