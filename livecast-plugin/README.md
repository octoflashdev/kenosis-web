# Kenosis AI — LiveCast plugin

A separate Android app bound by the offline **Kenosis AI** host over binder
(AIDL `IKenosisPlugin`, contract file copied byte-identical into both apps —
CI-enforced by `the plugin-contract CI check`). Part of the LiveCast
feature surface (realtime lecture transcription — shipping as a Beta feature
in the host app).

## What it does

When the host's LiveCast session runs, it pushes realtime transcript segments
(`livecast_push`) and periodic digests (`livecast_push_digest`) to this app.
This app serves the transcript to **any device on the same Wi-Fi**:

- `GET /` — the self-contained projector page (dark theme, auto-scroll,
  digest cards; no CDN — works fully offline)
- `GET /state?since=N&digestsSince=M` — the polling delta (JSON)

The LAN URL + QR code are shown in the host's LiveCast screen (the host reads
the bound port via `livecast_status`, port ladder 8090..8099).

## Privacy

The page is LAN-local read-only transcript state: no TLS, no auth, nothing
leaves the local network. Closing the host session unbinds the service and
shuts the server down. Unlike the Internet Search plugin, this app never
talks to the public internet — its INTERNET permission exists only because
Android requires it for a listening TCP socket.

## Tools (host-internal)

`livecast_status`, `livecast_reset`, `livecast_push`, `livecast_push_digest`.
These are NOT exposed to the on-device LLM — the host's chat tool round only
surfaces the Internet Search plugin's manifest.

## Build

```
source ~/android-development/env.sh
cd plugins/livecast
flutter pub get
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
# installs as hr.exel.kenosis.plugin_livecast.debug (discovery is
# action-based, so the suffix is invisible)
```

Local unit tests (pure state machine):

```
cd android && ./gradlew :app:testDebugUnitTest
```
