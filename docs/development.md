# Development

## Prerequisites

- Flutter 3.38+ stable (Windows host), Dart 3.10+
- Android: Android SDK (API 23+ min for WebRTC), JDK 17+
- Windows builds: **Visual Studio 2022 Build Tools** with "Desktop development with C++" (`flutter doctor` verifies)
- A [Supabase](https://supabase.com) project (free tier works)
- A LiveKit deployment for voice (self-hosted on any VPS, or LiveKit Cloud)

## 1. Configure the backend

```bash
supabase link --project-ref <your-ref>
supabase db push          # applies all migrations in order
```

Deploy the voice-token function and set its secrets:

```bash
supabase functions deploy voice-token
supabase secrets set \
  LIVEKIT_URL=wss://your-livekit.example.com \
  LIVEKIT_API_KEY=devkey_yourkey \
  LIVEKIT_API_SECRET=yoursecret
```

Auth: enable Email provider. For local/dev you can disable email confirmation; for production keep it on and handle the confirmation flow.

## 2. Configure the app

Two ways to hand the client its **public** config (never service keys):

**a. Compile-time (recommended for development)**

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=LIVEKIT_URL=wss://your-livekit.example.com
```

**b. First-run setup screen** — launch the app without defines and paste the URL + anon key once; they are stored in secure storage (encrypted on Android, DPAPI on Windows).

## 3. Run

```bash
flutter run -d windows    # Windows desktop
flutter run -d <device>   # Android device/emulator
```

## 4. Test

```bash
flutter analyze           # zero-issue policy
flutter test              # unit tests (gate, models, key mapping)
```

## 5. Build

```bash
# Android release APKs (per-ABI, much smaller installs)
flutter build apk --release --split-per-abi

# Windows release (requires VS Build Tools + Developer Mode for symlink support)
flutter build windows --release
```

Outputs: `build/app/outputs/flutter-apk/` and `build/windows/x64/runner/Release/`.

## Project conventions

- **Errors**: repositories throw `AppException(code, message)`; UI renders `message`, never raw exceptions.
- **New tables**: migration file + RLS policies + add to the realtime publication + model + repository. All five or none.
- **Realtime subscriptions**: always cancel in `dispose()`/`ref.onDispose()`. Grep for `.listen(` before merging a screen.
- **Secrets**: `--dart-define` or edge-function secrets only. The anon key is public by design; nothing else belongs in the client.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `flutter build windows` says "Visual Studio toolchain" missing | Install VS 2022 Build Tools + "Desktop development with C++" workload |
| "Building with plugins requires symlink support" | Enable Windows Developer Mode (Settings → System → For developers) |
| Gradle: `Unresolved reference: jvmTarget` in a plugin | That plugin needs a newer Kotlin Gradle plugin than your `settings.gradle.kts` pins |
| Voice joins fail with `VOICE_NOT_CONFIGURED` | Edge function secrets not set (`supabase secrets set LIVEKIT_…`) |
| Can hear nothing but join works | TURN not reachable from your network — check the LiveKit/TURN ports from a mobile connection |
| RLS error on a query you expected to work | The policy, not the query, is wrong — test with the SQL editor as the affected role |
