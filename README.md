# WeConnect

A lightweight, Discord-style communication app for **Windows and Android**: accounts, friends, private servers, real-time text channels, and multi-user voice channels (up to 20 participants) with both Voice Activity and Push-to-Talk.

Built with Flutter + Supabase (Auth / Postgres+RLS / Realtime) + LiveKit (WebRTC SFU). No web client.

## Status

| Piece | State |
|---|---|
| Schema + RLS migrations | ✅ complete (`supabase/migrations/`) |
| Auth, profiles, friends, servers, chat, voice | ✅ implemented |
| Windows global PTT hooks (C++) | ✅ implemented |
| Android voice + PTT button | ✅ implemented |
| Tests | ✅ 18/18 passing, `flutter analyze` clean |
| Android release APK | ✅ built (`app-arm64-v8a-release.apk`, 30.9 MB) |
| Windows release build | ⚠️ blocked on this machine: VS Build Tools installer cancels in non-interactive context — see `docs/development.md` |

## Quickstart

```bash
flutter pub get
supabase db push            # create schema + RLS
supabase functions deploy voice-token
supabase secrets set LIVEKIT_URL=... LIVEKIT_API_KEY=... LIVEKIT_API_SECRET=...

flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=LIVEKIT_URL=wss://your-livekit.example.com
```

Full setup (including the LiveKit VPS deployment): [docs/development.md](docs/development.md).

## Docs

- [Architecture](docs/architecture.md) — layers, why they exist
- [Database](docs/database.md) — tables, RLS, triggers, RPCs
- [Realtime](docs/realtime.md) — which system carries what, subscription hygiene
- [Voice](docs/voice.md) — SFU vs mesh, STUN/TURN, the shared VAD/PTT pipeline
- [Development](docs/development.md) — setup, build, troubleshooting

## Security model (short version)

- Postgres **RLS on every table**; deny-by-default. The anon key is public by design — RLS is the enforcement.
- LiveKit API keys and TURN credentials never leave the server; clients get a short-lived, room-scoped JWT from the `voice-token` edge function, which independently verifies membership and the 20-user cap.
- No secrets in the repo; all config arrives via `--dart-define` or the first-run setup screen (secure storage).
