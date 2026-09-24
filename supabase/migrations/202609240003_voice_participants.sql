-- ============================================================
-- WeConnect — voice channel occupancy tracking
-- 2026-09-24
--
-- This table mirrors LiveKit room occupancy for the UI and for the
-- server-side 20-user cap. The client voice service inserts a row on
-- join and deletes it on leave/disconnect. Realtime on this table
-- drives the "who's connected" list without polling.
--
-- NOTE: the authoritative gate is the voice-token edge function
-- (which re-counts at join time); this table is mirror state.
-- ============================================================

create table public.voice_participants (
  channel_id   uuid not null references public.channels(id) on delete cascade,
  profile_id   uuid not null references public.profiles(id) on delete cascade,
  server_id    uuid not null references public.servers(id) on delete cascade,
  joined_at    timestamptz not null default now(),
  primary key (channel_id, profile_id)
);
create index voice_participants_server_idx on public.voice_participants(server_id);

alter table public.voice_participants enable row level security;

create policy "voice_participants_select_member" on public.voice_participants
  for select to authenticated
  using (public.is_member_of(server_id, auth.uid()) or profile_id = auth.uid());

create policy "voice_participants_insert_self" on public.voice_participants
  for insert to authenticated
  with check (profile_id = auth.uid());

create policy "voice_participants_delete_self" on public.voice_participants
  for delete to authenticated
  using (profile_id = auth.uid());

-- Also add it to the realtime publication
alter publication supabase_realtime add table public.voice_participants;
