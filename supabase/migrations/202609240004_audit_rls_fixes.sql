-- ============================================================
-- WeConnect — audit fixes: RLS + RPC corrections
-- 2026-09-24
--
-- Fixes found by the full-project audit:
--
-- 1. server_members INSERT policy required role = 'member', but the app's
--    only join path is join_server_by_code() (SECURITY INVOKER), whose
--    insert into server_members runs with the caller's privileges — a plain
--    member insert is exactly what an invite join should create, and the
--    policy correctly allowed it. HOWEVER the policy also had to let the
--    trigger-inserted owner row be created (SECURITY DEFINER bypasses RLS,
--    so no change needed there). What WAS broken: nothing prevented a
--    caller from inserting a row for a server they cannot see (RLS on
--    servers is not consulted by the server_members INSERT policy), so a
--    user could self-grant membership in ANY private server by calling
--    join_server_by_code() with a guessed/leaked code. Now the policy
--    re-verifies the invite code server-side.
--
-- 2. user_settings had a FOR ALL policy — fine for UPDATE/DELETE/SELECT,
--    but the INSERT arm never fires on conflict-clause upserts for rows
--    that do not exist yet... actually FOR ALL covers INSERT; the real gap:
--    FOR ALL policies with only USING get WITH CHECK implied, that is OK.
--    Kept for documentation; replaced with explicit per-command policies.
--
-- 3. voice_participants had INSERT + DELETE but no UPDATE policy, while the
--    client upserts (channel_id, profile_id) to move between channels.
--    ON CONFLICT DO UPDATE needs UPDATE. Moving channels was silently
--    failing (a user who joined voice channel B while still registered in
--    voice channel A stayed "in" A for everyone else).
--
-- 4. leave_server (SECURITY INVOKER) deleted the whole server when the
--    owner was the last member, but servers DELETE RLS allows the owner
--    always — fine — yet the ownership-transfer UPDATE ran as invoker and
--    servers UPDATE RLS requires owner_id = auth.uid() in WITH CHECK;
--    transferring to another member violates it → the RPC raised a policy
--    exception and left ghost rows. Rewritten: transfer via a SECURITY
--    DEFINER helper, delete only via the RPC path.
-- ============================================================

-- ---------- 1. server_members: safe self-join via invite code ----------
drop policy if exists "server_members_insert_self" on public.server_members;
create policy "server_members_insert_self" on public.server_members
  for insert to authenticated
  with check (
    profile_id = auth.uid()
    and role = 'member'
    -- the server must actually hand out this code right now
    and exists (
      select 1 from public.servers s
      where s.id = server_id
        and s.invite_code = upper(current_setting('request.invite_code', true))
    )
  );

-- The RPC passes the (already validated) code through a GUC so the policy
-- can verify it without trusting the client. SECURITY INVOKER: the caller
-- still needs to satisfy the policy above.
create or replace function public.join_server_by_code(p_code text)
returns uuid language plpgsql security invoker set search_path = public as $$
declare
  v_server_id uuid;
begin
  if p_code is null or length(btrim(p_code)) = 0 then
    raise exception 'SERVER_NOT_FOUND';
  end if;

  select id into v_server_id
  from public.servers
  where invite_code = upper(btrim(p_code));
  if not found then
    raise exception 'SERVER_NOT_FOUND';
  end if;

  perform set_config('request.invite_code', upper(btrim(p_code)), true); -- transaction-scoped

  insert into public.server_members (server_id, profile_id)
  values (v_server_id, auth.uid())
  on conflict (server_id, profile_id) do nothing;

  return v_server_id;
end;
$$;

-- ---------- 2. user_settings: explicit per-command policies ----------
drop policy if exists "user_settings_all_own" on public.user_settings;
create policy "user_settings_select_own" on public.user_settings
  for select to authenticated using (id = auth.uid());
create policy "user_settings_insert_own" on public.user_settings
  for insert to authenticated with check (id = auth.uid());
create policy "user_settings_update_own" on public.user_settings
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "user_settings_delete_own" on public.user_settings
  for delete to authenticated using (id = auth.uid());

-- ---------- 3. voice_participants: allow the upsert (UPDATE) arm ----------
create policy "voice_participants_update_self" on public.voice_participants
  for update to authenticated
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

-- ---------- 4. leave_server without the invoker-policy loophole ----------
-- SECURITY DEFINER helper: transfer ownership even though the outgoing
-- owner can never satisfy servers_update_owner WITH CHECK for someone else.
create or replace function public._transfer_server_ownership(
  p_server_id uuid,
  p_new_owner uuid
) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.servers
  set owner_id = p_new_owner
  where id = p_server_id;
end;
$$;

revoke all on function public._transfer_server_ownership(uuid, uuid) from public, anon;
grant execute on function public._transfer_server_ownership(uuid, uuid) to authenticated;

create or replace function public.leave_server(p_server_id uuid)
returns void language plpgsql security invoker set search_path = public as $$
declare
  v_is_owner  boolean;
  v_next_owner uuid;
begin
  if not exists (
    select 1 from public.server_members
    where server_id = p_server_id and profile_id = auth.uid()
  ) then
    return; -- not a member: nothing to do
  end if;

  select exists (
    select 1 from public.servers
    where id = p_server_id and owner_id = auth.uid()
  ) into v_is_owner;

  if v_is_owner then
    select profile_id into v_next_owner
    from public.server_members
    where server_id = p_server_id and profile_id <> auth.uid()
    order by joined_at
    limit 1;

    if v_next_owner is null then
      -- Last member and owner: delete the server (owner-delete is allowed
      -- by servers_delete_owner RLS, evaluated as the owner).
      delete from public.servers where id = p_server_id and owner_id = auth.uid();
      return; -- cascades remove members/channels/messages
    end if;

    perform public._transfer_server_ownership(p_server_id, v_next_owner);
  end if;

  delete from public.server_members
  where server_id = p_server_id and profile_id = auth.uid();
end;
$$;

revoke all on function public.leave_server(uuid) from public, anon;
grant execute on function public.leave_server(uuid) to authenticated;
