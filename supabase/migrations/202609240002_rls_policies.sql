-- ============================================================
-- WeConnect — Row Level Security policies
-- 2026-09-24
-- Deny-by-default: every table has RLS enabled (migration 0001);
-- these policies grant the minimum access the app requires.
-- ============================================================

-- ============================================================
-- profiles: read any authenticated user (needed for search/dms),
-- update only your own row, never insert/delete directly
-- (rows are created by the on_auth_user_created trigger).
-- ============================================================
create policy "profiles_select_authenticated" on public.profiles
  for select to authenticated using (true);

create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Prevent privilege escalation / identity changes:
-- id, username, tag are immutable via the API.
create or replace function public.protect_profile_columns()
returns trigger language plpgsql as $$
begin
  if new.id <> old.id or new.username <> old.username or new.tag <> old.tag then
    raise exception 'IMMUTABLE_PROFILE_COLUMN';
  end if;
  return new;
end;
$$;

create trigger trg_protect_profile before update on public.profiles
for each row execute function public.protect_profile_columns();

-- ============================================================
-- friendships: both parties see the row.
-- Requester may create a pending row toward someone else,
-- the addressee may accept/decline it, either party may delete
-- (delete = remove friend / cancel request).
-- ============================================================
create policy "friendships_select_parties" on public.friendships
  for select to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());

create policy "friendships_insert_requester" on public.friendships
  for insert to authenticated
  with check (requester_id = auth.uid() and status = 'pending');

create policy "friendships_update_addressee" on public.friendships
  for update to authenticated
  using (addressee_id = auth.uid() and status = 'pending')
  with check (addressee_id = auth.uid() and status in ('accepted','declined'));

create policy "friendships_delete_parties" on public.friendships
  for delete to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());

-- Guard: you can only befriend/search people, not yourself
-- (also enforced by check constraint in schema).

-- ============================================================
-- servers: members can read; anyone authenticated can create
-- (creator becomes owner via trigger); only the owner can
-- update/delete the server itself.
-- ============================================================
create policy "servers_select_member" on public.servers
  for select to authenticated using (public.is_member(id));

create policy "servers_insert_authenticated" on public.servers
  for insert to authenticated with check (owner_id = auth.uid());

create policy "servers_update_owner" on public.servers
  for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy "servers_delete_owner" on public.servers
  for delete to authenticated using (owner_id = auth.uid());

-- ============================================================
-- server_members: visible to fellow members;
-- users manage their own membership row (join/leave);
-- owner can remove others.
-- ============================================================
create policy "server_members_select_cofeatured" on public.server_members
  for select to authenticated
  using (
    profile_id = auth.uid()
    or public.is_member_of(server_id, auth.uid())
  );

create policy "server_members_insert_self" on public.server_members
  for insert to authenticated
  with check (profile_id = auth.uid() and role = 'member');

create policy "server_members_delete_self_or_owner" on public.server_members
  for delete to authenticated
  using (
    profile_id = auth.uid()
    or exists (select 1 from public.servers s where s.id = server_members.server_id and s.owner_id = auth.uid())
  );

-- Membership rows are created either directly (join) or by the
-- security-definer trigger when a server is created.

-- ============================================================
-- channels: readable by server members; managed by server owner
-- ============================================================
create policy "channels_select_member" on public.channels
  for select to authenticated
  using (public.is_member(server_id));

create policy "channels_insert_owner" on public.channels
  for insert to authenticated
  with check (exists (select 1 from public.servers s where s.id = server_id and s.owner_id = auth.uid()));

create policy "channels_update_owner" on public.channels
  for update to authenticated
  using (exists (select 1 from public.servers s where s.id = server_id and s.owner_id = auth.uid()))
  with check (exists (select 1 from public.servers s where s.id = server_id and s.owner_id = auth.uid()));

create policy "channels_delete_owner" on public.channels
  for delete to authenticated
  using (exists (select 1 from public.servers s where s.id = server_id and s.owner_id = auth.uid()));

-- ============================================================
-- messages: send/read only in channels of servers you belong to;
-- you may edit/delete only your own messages.
-- ============================================================
create policy "messages_select_member" on public.messages
  for select to authenticated
  using (public.is_member(
    (select server_id from public.channels c where c.id = channel_id)
  ));

create policy "messages_insert_member" on public.messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and public.is_member((select server_id from public.channels c where c.id = channel_id))
  );

create policy "messages_update_sender" on public.messages
  for update to authenticated
  using (sender_id = auth.uid())
  with check (sender_id = auth.uid());

create policy "messages_delete_sender" on public.messages
  for delete to authenticated
  using (sender_id = auth.uid());

-- ============================================================
-- user_settings: strictly owner-only
-- ============================================================
create policy "user_settings_all_own" on public.user_settings
  for all to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- ============================================================
-- avatars storage bucket
-- ============================================================
insert into storage.buckets (id, name, public) values ('avatars','avatars', true)
on conflict (id) do nothing;

create policy "avatars_public_read" on storage.objects
  for select using (bucket_id = 'avatars');

create policy "avatars_owner_write" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars_owner_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars_owner_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ============================================================
-- Realtime: RLS-aware. supabase_realtime respects RLS for
-- postgres_changes; private channels use RLS-backed auth.
-- No extra grants needed beyond publication membership (0001).
-- ============================================================
