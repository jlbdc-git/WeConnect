-- ============================================================
-- WeConnect — server creation RLS convergence (42501 fix)
-- 2026-09-24
--
-- SYMPTOM: POST /rest/v1/servers → HTTP 403
--   { "code": "42501", "message": "new row violates row-level
--     security policy for table \"servers\"" }
--
-- ROOT CAUSE: the live project's servers INSERT policy diverged from the
-- local migrations. The dashboard-era policy required the OWNER column to
-- match on insert (owner_id = auth.uid()). That forbids every legitimate
-- create that omits owner_id (letting the DB default fill it) or that lets
-- the client compute it:
--
--   insert {'name': 'x', 'owner_id': <uid>}   -- ok ONLY if uid matches
--   insert {'name': 'x'}                      -- owner_id = auth.uid()
--                                             -- DEFAULT → always rejected
--
-- Any owner_id drift (different session identity, metadata fetch, or a
-- client that sends profiles.id instead of auth uid) trips it too.
--
-- FIX: the INSERT policy must only require that the caller is
-- authenticated and that the row's owner is THE CALLER THEMSELVES. It must
-- NOT reference how owner_id got into the payload. Migration 0001 already
-- sets owner_id DEFAULT auth.uid(), so:
--
--   • authenticated + owner_id = auth.uid()  → the only legitimate create
--   • impersonation (owner_id = someone else) → rejected by the policy
--     AND by servers_owner_fk → profiles(id): you cannot insert someone
--     else as owner.
--
-- The creator automatically becomes 'owner' in server_members via the
-- handle_new_server() SECURITY DEFINER trigger (0001) — no client-side
-- member insert exists, and none is needed.
--
-- This migration REPLACES the policies idempotently (drop if exists +
-- create) so a stale remote converges to the correct set with no
-- duplicates. RLS itself is never disabled.
-- ============================================================

-- ---------- servers: replace all four policies with canonical set ----------
drop policy if exists "servers_select_member" on public.servers;
drop policy if exists "servers_insert_authenticated" on public.servers;
drop policy if exists "servers_insert_own" on public.servers;
drop policy if exists "servers_update_owner" on public.servers;
drop policy if exists "servers_delete_owner" on public.servers;

create policy "servers_select_member" on public.servers
  for select to authenticated using (public.is_member(id));

create policy "servers_insert_own" on public.servers
  for insert to authenticated
  with check (owner_id = auth.uid());

create policy "servers_update_owner" on public.servers
  for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy "servers_delete_owner" on public.servers
  for delete to authenticated using (owner_id = auth.uid());

-- ---------- handle_new_server: idempotent owner-member insert ----------
-- The trigger that inserts the creator into server_members used a bare
-- insert; if a row already existed (e.g. a retried request), the PK
-- conflict would abort the whole server INSERT. Guard it. SECURITY DEFINER
-- bypasses RLS by design — this is trusted server-side automation, not a
-- client path.
create or replace function public.handle_new_server()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.server_members (server_id, profile_id, role)
  values (new.id, new.owner_id, 'owner')
  on conflict (server_id, profile_id) do nothing;
  return new;
end;
$$;

-- ---------- Diagnostics companion ----------
-- supabase/diagnostics/servers_rls_check.sql prints the policies actually
-- live on the remote (run in the SQL editor if 42501 ever recurs):
--   select policyname, cmd, qual, with_check
--   from pg_policies where schemaname='public' and tablename='servers';
-- Expected: exactly four rows — select_member / insert_own /
-- update_owner / delete_owner, with insert_own.with_check = (owner_id = auth.uid()).
