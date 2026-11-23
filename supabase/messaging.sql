-- SABKA HISSA: secure Admin <-> Member cloud messaging
-- Run once in the Supabase SQL Editor for project atrxdrxucpaidtamfrmz.
create table if not exists public.member_messages (
  id uuid primary key default gen_random_uuid(),
  member_id text not null,
  sender_user_id uuid not null references auth.users(id) on delete cascade,
  sender_role text not null check (sender_role in ('admin','member')),
  body text not null default '',
  photo_path text,
  created_at timestamptz not null default now(),
  constraint member_messages_body_or_photo check (length(trim(body)) > 0 or photo_path is not null)
);

create index if not exists member_messages_member_created_idx
  on public.member_messages (member_id, created_at desc);

alter table public.member_messages enable row level security;

drop policy if exists "member_messages_admin_read" on public.member_messages;
create policy "member_messages_admin_read" on public.member_messages
for select to authenticated
using (lower(coalesce(auth.jwt() ->> 'email','')) = 'acharya.kp65@gmail.com');

drop policy if exists "member_messages_member_read" on public.member_messages;
create policy "member_messages_member_read" on public.member_messages
for select to authenticated
using (exists (
  select 1 from public.member_login_accounts a
  where a.auth_user_id = auth.uid()
    and a.member_id = member_messages.member_id
    and a.is_active = true
));

drop policy if exists "member_messages_admin_insert" on public.member_messages;
create policy "member_messages_admin_insert" on public.member_messages
for insert to authenticated
with check (
  lower(coalesce(auth.jwt() ->> 'email','')) = 'acharya.kp65@gmail.com'
  and sender_user_id = auth.uid()
  and sender_role = 'admin'
);

drop policy if exists "member_messages_member_insert" on public.member_messages;
create policy "member_messages_member_insert" on public.member_messages
for insert to authenticated
with check (
  sender_user_id = auth.uid()
  and sender_role = 'member'
  and exists (
    select 1 from public.member_login_accounts a
    where a.auth_user_id = auth.uid()
      and a.member_id = member_messages.member_id
      and a.is_active = true
  )
);

drop policy if exists "member_messages_admin_delete" on public.member_messages;
create policy "member_messages_admin_delete" on public.member_messages
for delete to authenticated
using (lower(coalesce(auth.jwt() ->> 'email','')) = 'acharya.kp65@gmail.com');

drop policy if exists "member_messages_sender_delete" on public.member_messages;
create policy "member_messages_sender_delete" on public.member_messages
for delete to authenticated
using (sender_user_id = auth.uid());

-- Private photo bucket. Object path format: <member_id>/<unique-file-name>.jpg
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('member-chat-photos','member-chat-photos',false,524288,'{image/jpeg,image/png,image/webp}')
on conflict (id) do update set public=false, file_size_limit=524288,
  allowed_mime_types='{image/jpeg,image/png,image/webp}';

drop policy if exists "member_chat_photo_read" on storage.objects;
create policy "member_chat_photo_read" on storage.objects
for select to authenticated
using (
  bucket_id = 'member-chat-photos'
  and (
    lower(coalesce(auth.jwt() ->> 'email','')) = 'acharya.kp65@gmail.com'
    or exists (
      select 1 from public.member_login_accounts a
      where a.auth_user_id = auth.uid()
        and a.member_id = (storage.foldername(name))[1]
        and a.is_active = true
    )
  )
);

drop policy if exists "member_chat_photo_upload" on storage.objects;
create policy "member_chat_photo_upload" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'member-chat-photos'
  and (
    lower(coalesce(auth.jwt() ->> 'email','')) = 'acharya.kp65@gmail.com'
    or exists (
      select 1 from public.member_login_accounts a
      where a.auth_user_id = auth.uid()
        and a.member_id = (storage.foldername(name))[1]
        and a.is_active = true
    )
  )
);

drop policy if exists "member_chat_photo_delete" on storage.objects;
create policy "member_chat_photo_delete" on storage.objects
for delete to authenticated
using (
  bucket_id = 'member-chat-photos'
  and lower(coalesce(auth.jwt() ->> 'email','')) = 'acharya.kp65@gmail.com'
);

-- Enable Realtime for the new message table without failing if already added.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'member_messages'
  ) then
    alter publication supabase_realtime add table public.member_messages;
  end if;
exception when undefined_object then
  null;
end $$;
