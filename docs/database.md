# Database

PostgreSQL via Supabase. All schema lives in versioned migrations under `supabase/migrations/` — apply with `supabase db push` (never edit the dashboard schema directly for changes the app depends on).

## Tables

```
profiles ──┬── friendships (self-pairing social graph)
           ├── servers (owner) ──┬── server_members
           │                     └── channels ──┬── messages
           └── user_settings                     └── voice_participants
auth.users ── profiles.id (1:1, ON DELETE CASCADE)
```

| Table | Purpose | Notable constraints |
|---|---|---|
| `profiles` | Public user data (no auth secrets) | `citext` unique username, 4-digit tag, `id` FK → `auth.users` |
| `friendships` | One row per pair, `pending`/`accepted`/`declined` | canonical ordering `requester_id < addressee_id` + unique pair → no duplicate/reverse rows |
| `servers` | Private groups | `invite_code` unique 8-char, owner FK |
| `server_members` | Membership, PK `(server_id, profile_id)` → join is idempotent | role check `owner`/`member` |
| `channels` | `text` or `voice`, per-server ordering | unique `(server_id, name)`, name regex `^[a-z0-9-]{1,32}$` |
| `messages` | Chat | content 1..4000 chars, index `(channel_id, created_at desc)` for keyset pagination |
| `user_settings` | Voice/theme/PTT per user, PK = profile id | CHECK constraints on voice_mode, theme, mouse button |
| `voice_participants` | Mirrors LiveKit occupancy for UI + server-side 20-user cap | PK `(channel_id, profile_id)` |

## Triggers (automation, not client-trusted)

- `on_auth_user_created` → auto-creates `profiles` row (username from email/meta + id suffix) and (via cascade) the `user_settings` row.
- `on_server_created` → inserts owner into `server_members` and creates `#general` (text) + `#voice` (voice) channels.
- `protect_profile_columns` → blocks client-side updates to `id`, `username`, `tag` (immunizes against privilege escalation).
- `set_updated_at` → maintains `friendships.updated_at`.

## RPCs

- `is_member(p_server_id)` / `is_member_of(p_server_id, p_profile_id)` — SECURITY DEFINER helpers so RLS policies can test membership **without infinite recursion** on `server_members` (a policy querying its own table errors out in Postgres).
- `join_server_by_code(p_code)` — atomic join; the unique PK makes concurrent joins safe.
- `leave_server(p_server_id)` — owner-leave transfers ownership to the oldest member, or deletes the server when empty.

## RLS summary (migration 0002 — deny-by-default)

| Table | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| profiles | any authenticated user (search) | — (trigger only) | own row, immutable columns guarded | — |
| friendships | rows involving you | you as sender, pending | addressee can accept/decline | either party (unfriend/cancel) |
| servers | members only | you as owner | owner | owner |
| server_members | you or co-members | yourself, as member | — | yourself or server owner |
| channels | members only | server owner | server owner | server owner |
| messages | members of the channel's server | yourself + member | yourself | yourself |
| user_settings | own row | own row | own row | own row |
| voice_participants | co-members | yourself | — | yourself |
| storage `avatars/{uid}/*` | public read | own folder | own folder | own folder |

**Test your policies** after enabling: sign in as two different users and confirm a user cannot read another server's messages by guessing a channel id (RLS returns empty, not an error).

## Realtime publication (migration 0001)

`profiles`, `friendships`, `servers`, `channels`, `messages`, `user_settings`, `voice_participants` are added to `supabase_realtime`. Supabase Realtime respects RLS for postgres_changes/streams — subscribers only receive rows they could SELECT.

## Applying migrations

```bash
supabase link --project-ref <your-ref>
supabase db push
```

Or paste each migration into the dashboard SQL editor in filename order (20260924_0001 → 0002 → 0003).
