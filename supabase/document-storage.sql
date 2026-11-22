-- SABKA HISSA: private document storage
-- Run this once in Supabase SQL Editor.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('sabka-hissa-docs','sabka-hissa-docs',false,15728640,
  array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public=false, file_size_limit=15728640,
  allowed_mime_types=excluded.allowed_mime_types;

create table if not exists public.document_files (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  record_type text not null,
  record_id text not null,
  file_name text not null,
  mime_type text not null,
  storage_path text not null unique,
  file_size bigint not null,
  created_at timestamptz not null default now()
);
alter table public.document_files enable row level security;
drop policy if exists "Users read own document metadata" on public.document_files;
create policy "Users read own document metadata" on public.document_files
for select to authenticated using (auth.uid() = user_id);
drop policy if exists "Users insert own document metadata" on public.document_files;
create policy "Users insert own document metadata" on public.document_files
for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users delete own document metadata" on public.document_files;
create policy "Users delete own document metadata" on public.document_files
for delete to authenticated using (auth.uid() = user_id);

drop policy if exists "Users upload own files" on storage.objects;
create policy "Users upload own files" on storage.objects
for insert to authenticated with check (
  bucket_id = 'sabka-hissa-docs' and (storage.foldername(name))[1] = auth.uid()::text
);
drop policy if exists "Users read own files" on storage.objects;
create policy "Users read own files" on storage.objects
for select to authenticated using (
  bucket_id = 'sabka-hissa-docs' and (storage.foldername(name))[1] = auth.uid()::text
);
drop policy if exists "Users delete own files" on storage.objects;
create policy "Users delete own files" on storage.objects
for delete to authenticated using (
  bucket_id = 'sabka-hissa-docs' and (storage.foldername(name))[1] = auth.uid()::text
);
