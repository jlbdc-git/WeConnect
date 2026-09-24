# Voice

Audio-only, SFU-based, up to 20 participants per voice channel. No peer-to-peer mesh.

## Why an SFU (and not P2P mesh)

In a mesh, every participant uploads their audio N-1 times. At 20 users that is 19 upstream streams per client — home/mobile uplinks die long before that. An **SFU (Selective Forwarding Unit)** changes the math: each client uploads **once** to the server, which forwards copies to everyone else. Upstream stays constant regardless of room size.

```
mesh:  A→B A→C ... B→A B→C ...   O(N²) upstream per client: N-1 streams
SFU:   A→SFU, B→SFU, C→SFU       SFU→everyone. 1 upload per client.
```

We use **LiveKit** (open-source SFU, Go/Pion) because it has an official Flutter SDK, a single-binary Docker deployment, built-in TURN, and per-room JWT auth.

## Signaling, STUN, TURN — who does what

| Piece | Job | Where it lives here |
|---|---|---|
| **Signaling** | Exchanging SDP (codec/transport offers) and ICE candidates so peers can find each other | LiveKit's WebSocket protocol — the client SDK does this inside `Room.connect()` |
| **STUN** | "What is my public IP:port?" — lets two peers attempt a direct path | Public servers + LiveKit's built-in; embedded by the SDK |
| **TURN** | Relay fallback when direct paths fail (symmetric NAT, corporate firewalls, some mobile carriers) | LiveKit's built-in TURN (coturn) on your VPS; credentials are server-side |
| **SFU** | Receives, routes and forwards media | LiveKit server |
| **Media** | The audio itself | DTLS-SRTP between client and SFU |

Rule of thumb: **signaling introduces, ICE connects, TURN relays when ICE fails, the SFU forwards.**

## The auth chain (secrets never ship to the client)

```
Client                          Edge Function (voice-token)            LiveKit
  │  POST /voice-token               │                                  │
  │  + Supabase JWT ────────────────▶│ verify JWT                       │
  │                                  │ check channel is voice           │
  │                                  │ check membership in Postgres     │
  │                                  │ count occupancy (20-user cap)    │
  │                                  │ mint HS256 JWT (2h TTL, room-    │
  │                                  │  scoped, identity = user id)     │
  │◀─── { token, url, roomName } ────│                                  │
  │                                                                     │
  │  Room.connect(url, token) ─────────────────────────────────────────▶│
```

`LIVEKIT_API_KEY/SECRET` and TURN credentials live only in edge-function secrets / server config. The client receives a scoped, expiring JWT and nothing else.

## The shared audio pipeline (one gate, two modes)

```
microphone
  → WebRTC audio processing (noise suppression, echo cancellation, AGC
    — configured via AudioCaptureOptions, provided by the platform's
    WebRTC audio stack, not reimplemented)
  → VoiceGate  ← the mode-agnostic gate (lib/core/services/voice_gate.dart)
  → LiveKit publisher (Opus, DTX on, RED on)
  → SFU
  → other participants → local playback
```

`VoiceGate` toggles `track.enabled` on the local mic track — the WebRTC-level contract for "capture and send nothing". Modes differ only in what drives the gate:

### Mode 1 — Voice Activity (automatic)
- The published track stays **open**; **Opus DTX** (Discontinuous Transmission) is enabled at publish time, so when you are silent the codec simply stops emitting packets — nothing is transmitted, with zero gate latency.
- The **speaking indicator** uses LiveKit's server-side active-speaker detection (`ActiveSpeakersChangedEvent`), which is real VAD on the received streams — including your own, so the UI ring lights up when the server hears you.
- `vadSensitivity` (0–100) sets the hold-open window (150–950 ms) so the indicator doesn't flicker between words.

### Mode 2 — Push-to-Talk
- The gate is **closed** until an input event opens it. Windows: global low-level keyboard/mouse hooks (see below). Android: the on-screen hold-to-talk button. The gate closes on release; mute overrides an active press.

## Windows PTT (global hooks)

`windows/runner/ptt_hooks.cpp` installs **WH_KEYBOARD_LL / WH_MOUSE_LL** low-level hooks in the runner process. These receive input for the whole desktop session, so PTT works while the app is **unfocused** — the same mechanism Discord uses. The hook proc only forwards an event over the `weconnect/platform` MethodChannel (a slow hook proc gets Windows to drop it); all policy stays in Dart.

- Keys: letters A–Z, Space, LAlt/RCtrl (left-side modifiers), CapsLock, Tab — mapped to virtual-key codes in `pttKeyNameToVk`.
- Mouse: XBUTTON1 (back), XBUTTON2 (forward), middle click.
- Limitations (documented, not hidden): low-level hooks can be blocked by UIPI when an *elevated* (admin) app has focus — this affects every non-admin app including Discord; and hooks cannot distinguish "game capture" scenarios. Everything else works globally.

## Android PTT

No global input hooks exist on Android (by design, for security). PTT is a large (132 px) press-and-hold button rendered in the voice panel: `onLongPressStart/End/Cancel` map to gate open/close. States are visually distinct: Ready (brand color) → Transmitting (green ring) → Muted (grey, shows MUTED).

## Controls & semantics

| Control | Implementation | Remote effect |
|---|---|---|
| Mute | gate closes + `setMicrophoneEnabled(false)` | others see the mute indicator |
| Deafen | remote audio publications `.disable()` locally | others see nothing; you hear nothing |
| Leave | delete `voice_participants` row + `Room.disconnect()` | occupancy updates via realtime |

## Reconnection

`RoomReconnectingEvent` → UI shows "Reconnecting…" (orange); `RoomReconnectedEvent` → back to green; `RoomDisconnectedEvent` → full cleanup (gate, listeners, room) so a dead session never lingers. The occupancy row is deleted on disconnect, so after a crash other users see the participant leave rather than a ghost.

## Deployment checklist (VPS)

1. Run LiveKit with a config exposing **443 (TLS WebSocket)** for signaling and the **UDP port range** for media; enable its embedded TURN.
2. `supabase secrets set LIVEKIT_URL=wss://… LIVEKIT_API_KEY=… LIVEKIT_API_SECRET=…`
3. Verify ICE connectivity from a mobile network (not just office/home Wi-Fi) — that is the path TURN exists for.
