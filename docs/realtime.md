# Realtime

Two completely different realtime systems are in play — do not confuse them:

| | Supabase Realtime | WebRTC (LiveKit) |
|---|---|---|
| Carries | app events: new messages, friend-request changes, voice occupancy | voice audio frames |
| Transport | WebSocket + Postgres logical replication | SRTP/UDP (ICE-negotiated) to the SFU |
| Auth | your Supabase JWT + RLS | short-lived LiveKit room JWT from the edge function |
| Used for | chat, friends, participants list | the actual microphone audio |

Supabase Realtime is never used for media — it cannot handle sustained audio. LiveKit is never used for app state — it is not a database.

## Where each stream lives

| Stream | Source | Consumer | Cancelled in |
|---|---|---|---|
| Auth state | `supabase.auth.onAuthStateChange` | `authStateProvider` → router | app lifetime (provider-scoped) |
| Chat messages | `MessageRepository.subscribeMessages` (postgres_changes on `messages`) | `ChatController` | `ref.onDispose` when leaving a channel |
| Friend list | `friendships` stream | `FriendsController` | `ref.onDispose` |
| Voice participants | `voice_participants` stream | `VoiceChannelParticipants` widget | widget `dispose()` |
| LiveKit room events | `Room.createListener()` | `VoiceService` | `_cleanup()` |

## Deduplication rules

- Chat: the sending client does **not** optimistically append. The row comes back from the `insert().select()` and again via realtime; `ChatController` drops ids it already has. This keeps ordering authoritative server-side and avoids "message appears twice" bugs.
- Friends: any change to a relevant `friendships` row triggers a full refetch of the (small) list — simpler and safer than diffing change events.

## Reconnect behavior

- **Supabase Realtime** reconnects automatically with exponential backoff; postgres_changes subscriptions resume from re-sync, not from a cursor, so a brief gap can miss events while offline (chat compensates by refetching the latest page on channel re-entry).
- **LiveKit** emits `RoomReconnectingEvent` / `RoomReconnectedEvent`; `VoiceService` maps these to UI state so users see "Reconnecting…". A final `RoomDisconnectedEvent` tears the session down and resets state.
- The `voice_participants` row is deleted on leave/disconnect so occupancy stays truthful after crashes (stale rows are also bounded by the FK cascade on channel delete).

## Subscription hygiene (avoiding the classic leaks)

1. Every `StreamSubscription` is stored in a field and cancelled in `dispose()`/`ref.onDispose()` — no anonymous subscriptions.
2. Family providers (`chatControllerProvider(channelId)`) auto-dispose when the last listener goes away, which also cancels their realtime sub.
3. `VoiceChannelParticipants` re-subscribes on `didUpdateWidget` when the channel id changes — never two live subs for old + new channel.
