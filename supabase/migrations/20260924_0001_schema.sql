-- ============================================================
-- WeConnect — initial schema
-- 2026-09-24
-- ============================================================

create extension if not exists pgcrypto;        -- gen_random_uuid()
create extension if not exists citext;          -- case-insensitive usernames

-- ---------- enums ----------
create type friendship_status as enum ('pending', 'accepted', 'declined');
create type channel_kind       as enum ('text', 'voice');

-- ============================================================
-- profiles  (1-1 with auth.users)
-- ============================================================
create table public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  username     citext unique not null check (username ~ '^[a-z0-9_\.]{3,32}$'),
  display_name text not null default '' check (char_length(display_name) <= 64),
  avatar_url   text,
  tag          smallint not null default (floor(random()*9000)+1000)::smallint check (tag between 1000 and 9999),
  last_seen_at timestamptz not null default now()
);

-- Autonaming: display_name defaults to username
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'username',''), split_part(new.email,'@',1)) ||
      '_' || substr(replace(new.id::text,'-',''),1,6),
    coalesce(nullif(new.raw_user_meta_data->>'display_name',''), '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- ============================================================
-- friendships  (bidirectional — store one row per pair)
-- ============================================================
create table public.friendships (
  id           uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status       friendship_status not null default 'pending',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint no_self_friendship check (requester_id <> addressee_id)
);
-- One row per unordered pair, regardless of direction: the expression
-- index normalizes (a,b) and (b,a) to the same key. True direction is
-- preserved in the columns (requester_id = actual sender), which RLS
-- relies on: only the addressee may accept/decline.
create unique index friendship_pair_unique
  on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index friendships_requester_idx on public.friendships(requester_id);
create index friendships_addressee_idx on public.friendships(addressee_id);

-- ============================================================
-- servers
-- ============================================================
create table public.servers (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(name) between 1 and 64),
  icon_url   text,
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  invite_code text unique not null default upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),
  created_at timestamptz not null default now()
);

-- ============================================================
-- server_members
-- ============================================================
create table public.server_members (
  server_id  uuid not null references public.servers(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  role       text not null default 'member' check (role in ('owner','member')),
  joined_at  timestamptz not null default now(),
  primary key (server_id, profile_id)
);
create index server_members_profile_idx on public.server_members(profile_id);

-- auto-insert owner as member when a server is created
create or replace function public.handle_new_server()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.server_members (server_id, profile_id, role) values (new.id, new.owner_id, 'owner');
  return new;
end;
$$;

create trigger on_server_created
after insert on public.servers
for each row execute function public.handle_new_server();

-- ============================================================
-- channels
-- ============================================================
create table public.channels (
  id         uuid primary key default gen_random_uuid(),
  server_id  uuid not null references public.servers(id) on delete cascade,
  name       text not null check (name ~ '^[a-z0-9-]{1,32}$'),
  kind       channel_kind not null default 'text',
  position   int not null default 0,
  created_at timestamptz not null default now(),
  unique (server_id, name)
);
create index channels_server_idx on public.channels(server_id);

-- default channels when a server is created
create or replace function public.handle_new_server_channels()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.channels (server_id, name, kind, position) values
    (new.id, 'general', 'text', 0),
    (new.id, 'voice',   'voice', 0);
  return new;
end;
$$;

create trigger on_server_channels_created
after insert on public.servers
for each row execute function public.handle_new_server_channels();

-- ============================================================
-- messages
-- ============================================================
create table public.messages (
  id         uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.channels(id) on delete cascade,
  sender_id  uuid not null references public.profiles(id) on delete cascade,
  content    text not null check (char_length(content) between 1 and 4000),
  created_at timestamptz not null default now(),
  edited_at  timestamptz
);
create index messages_channel_created_idx on public.messages(channel_id, created_at desc);

-- ============================================================
-- user_settings
-- ============================================================
create table public.user_settings (
  id          uuid primary key references public.profiles(id) on delete cascade,
  theme       text not null default 'system' check (theme in ('system','light','dark')),
  voice_mode  text not null default 'voice_activity' check (voice_mode in ('voice_activity','push_to_talk')),
  ptt_key     text not null default 'V',
  ptt_mouse_button int not null default 0 check (ptt_mouse_button in (0,4,5,6)),  -- 0=none,4=XB1,5=XB2,6=middle
  mic_device_id  text,
  speaker_device_id text,
  noise_suppression boolean not null default true,
  echo_cancellation boolean not null default true,
  auto_gain_control boolean not null default true,
  vad_sensitivity   smallint not null default 50 check (vad_sensitivity between 0 and 100),
  updated_at     timestamptz not null default now()
);

-- auto-create settings row for every new profile
create or replace function public.handle_new_profile_settings()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.user_settings (id) values (new.id) on conflict do nothing;
  return new;
end;
$$;

create trigger on_profile_created_settings
after insert on public.profiles
for each row execute function public.handle_new_profile_settings();

-- ============================================================
-- updated_at trigger (generic)
-- ============================================================
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_friendships_updated before update on public.friendships
for each row execute function public.set_updated_at();

-- ============================================================
-- RPC: is_member(server) — SECURITY DEFINER to avoid recursive RLS
-- ============================================================
create or replace function public.is_member(p_server_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from public.server_members
    where server_id = p_server_id and profile_id = auth.uid()
  );
$$;

-- SECURITY DEFINER helper so policies on server_members can check
-- membership WITHOUT recursing into server_members' own RLS
-- (a policy that queries its own table raises "infinite recursion").
create or replace function public.is_member_of(p_server_id uuid, p_profile_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from public.server_members
    where server_id = p_server_id and profile_id = p_profile_id
  );
$$;

-- ============================================================
-- RPC: join_server_by_code
-- ============================================================
create or replace function public.join_server_by_code(p_code text)
returns uuid language plpgsql security invoker as $$
declare
  v_server_id uuid;
begin
  select id into v_server_id from public.servers where invite_code = upper(p_code);
  if not found then
    raise exception 'SERVER_NOT_FOUND';
  end if;
  insert into public.server_members (server_id, profile_id) values (v_server_id, auth.uid())
  on conflict (server_id, profile_id) do nothing;
  return v_server_id;
end;
$$;

-- ============================================================
-- RPC: leave_server
-- ============================================================
create or replace function public.leave_server(p_server_id uuid)
returns void language plpgsql security invoker as $$
begin
  -- owner leaving transfers ownership to the oldest member, or deletes if last
  if exists (select 1 from public.servers where id = p_server_id and owner_id = auth.uid()) then
    delete from public.servers where id = p_server_id and owner_id = auth.uid()
      and not exists (select 1 from public.server_members sm where sm.server_id = p_server_id and sm.profile_id <> auth.uid());
    if exists (select 1 from public.servers where id = p_server_id) then
      update public.servers set owner_id = (
        select profile_id from public.server_members where server_id = p_server_id and profile_id <> auth.uid()
        order by joined_at limit 1
      ) where id = p_server_id;
    end if;
  end if;
  delete from public.server_members where server_id = p_server_id and profile_id = auth.uid();
end;
$$;

-- ============================================================
-- Enable realtime publication (tables; columns default = all)
-- ============================================================
alter publication supabase_realtime add table public.profiles;
alter publication supabase_realtime add table public.friendships;
alter publication supabase_realtime add table public.servers;
alter publication supabase_realtime add table public.channels;
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.user_settings;

-- Enable RLS on every table (policies in next migration)
alter table public.profiles      enable row level security;
alter table public.friendships   enable row level security;
alter table public.servers       enable row level security;
alter table public.server_members enable row level security;
alter table public.channels      enable row level security;
alter table public.messages      enable row level security;
alter table public.user_settings enable row level security;
