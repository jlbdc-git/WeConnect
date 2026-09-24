# Architecture

WeConnect is a lightweight Discord-style chat + voice app for **Windows and Android**, built with Flutter. One codebase, one backend, two native targets. No web client.

## The 30-second map

```
┌─────────────────────────── Flutter app (Dart) ───────────────────────────┐
│  UI (features/*/)   →   Controllers (Riverpod)   →   Repositories        │
│  login, friends,        auth, friends, chat,         core/repositories/  │
│  chat, voice, settings  voice, settings                                  │
│        │                        │                        │               │
│        │                        │                        ▼               │
│        │                        │              ┌─────────────────────┐   │
│        │                        │              │  Services           │   │
│        │                        │              │  voice (LiveKit)    │   │
│        │                        │              │  platform (PTT)     │   │
│        │                        │              └─────────────────────┘   │
└────────┼────────────────────────┼───────────────────────┬────────────────┘
         │                        │                       │
         ▼                        ▼                       ▼
   Supabase Auth           Supabase Realtime        LiveKit SFU (WebRTC)
   Postgres + RLS          (app events)             (audio media only)
```

Key separation: **Supabase never carries voice audio.** Postgres/Realtime handle app state; a self-hosted LiveKit SFU carries the actual WebRTC media (see [voice.md](voice.md)).

## Layers

| Layer | Location | Responsibility |
|---|---|---|
| Models | `lib/core/models/` | Plain data classes (`Profile`, `Message`, `Server`…). JSON mapping only, no logic. |
| Repositories | `lib/core/repositories/` | All Supabase I/O. Throw `AppException`; UI never sees Postgrest errors. |
| Services | `lib/core/services/` | Cross-cutting engines: `VoiceService` (LiveKit), `VoiceGate` (VAD/PTT), `PlatformService` (native PTT hooks). |
| State | `lib/core/state/providers.dart` + `lib/features/*/[feature]_controller.dart` | Riverpod 2.x. Controllers own mutable state; providers wire dependencies. |
| UI | `lib/features/*/` | Screens/widgets per feature. Widgets call controllers, never repositories. |
| Platform | `windows/runner/ptt_hooks.cpp`, Android manifest | Native code kept out of Dart's way behind a single MethodChannel. |

## Why this shape

- **Repository-per-table** keeps Supabase query syntax from leaking into widgets; when a query changes, one file changes.
- **Riverpod (not setState/Bloc)**: compile-safe DI, easy test overrides, works identically on Windows/Android. Pinned to 2.6.x for the stable Notifier API.
- **One `VoiceService` instance** (a Riverpod singleton) owns the LiveKit room — voice state can't diverge between screens.
- **`VoiceGate` is transport-agnostic** (depends on a 2-property `GateTrack` interface, not the LiveKit type) so both voice modes and tests share one pipeline.

## Realtime & lifecycle rules

- Every StreamSubscription is cancelled in `dispose()` / `ref.onDispose()`. The realtime chat and voice-participant streams follow this pattern (see `chat_controller.dart`, `voice_participants_list.dart`).
- Auth state is a single `StreamProvider` (`authStateProvider`) — the router reacts to it; nothing else polls auth.
- The LiveKit `Room` is disposed in `VoiceService._cleanup()`; leaving a channel tears down gate, listeners and room in one path.

## Platform split

- **Windows**: global PTT hooks live in C++ (`windows/runner/ptt_hooks.cpp`) — low-level WH_KEYBOARD_LL / WH_MOUSE_LL hooks installed by the runner and exposed to Dart via one MethodChannel (`weconnect/platform`). Dart never touches `windows.h`.
- **Android**: no global input hooks exist; the PTT control is a large press-and-hold widget (`voice_panel.dart`) plus standard lifecycle handling. Mic permission is declared in the manifest and requested by the OS when the user first joins voice.

## Folder tree

```
lib/
  main.dart                 entrypoint: config load, Supabase init, DI overrides
  core/
    config/app_config.dart  runtime config (dart-define or secure storage)
    constants/ errors/ models/ navigation/ repositories/ services/ state/ theme/ utils/
  features/
    auth/     login + register screens, auth controller
    chat/     chat screen + controller (pagination, realtime)
    friends/  friends screen + controller (requests, realtime)
    home/     responsive shell (desktop 3-pane / mobile nav)
    servers/  server rail, channel sidebar, servers controller
    settings/ settings screen/controller, first-run setup screen
    voice/    voice panel, voice controller, participants list
supabase/
  migrations/               schema + RLS (apply with supabase db push)
  functions/voice-token/    edge function: LiveKit JWT minting
windows/runner/             Flutter template + ptt_hooks.cpp (global PTT)
android/app/                manifest (mic permission), gradle config
```
