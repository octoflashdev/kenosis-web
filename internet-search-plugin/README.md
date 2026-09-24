# Kenosis Internet Search Plugin

`kenosis_plugin_internet` — the internet-isolated plugin app for [Kenosis AI](https://www.kenosis-ai.com).

Kenosis AI is an **offline-first** on-device AI assistant: the host app holds no
`INTERNET` permission and cannot touch the network. This plugin is the **only
component in the ecosystem with network access**. The host app discovers it,
binds it over a **LOCAL AIDL binder**, and calls its tools to fetch live web
content. The host and plugin are separate Android applications (separate APKs,
separate packages); they talk only over the binder, never over a socket.

## The plugin contract

Both apps ship an identical copy of
`android/app/src/main/aidl/hr/exel/kenosis/plugin/IKenosisPlugin.aidl`:

```aidl
package hr.exel.kenosis.plugin;

interface IKenosisPlugin {
    String getManifest();               // JSON tool manifest
    String invoke(String toolName, String paramsJson);  // JSON {ok, data|error}
}
```

The host binds the service declared in `AndroidManifest.xml` by the intent
action `hr.exel.kenosis_ai.PLUGIN_SERVICE`, calls `getManifest()` once per attach
to learn the tool list, then `invoke()` per tool call. The tool manifest is
served over the binder — it is NOT duplicated in manifest `<meta-data>`.

## Tools

### `web_search`
Search the public web and return a text observation. The host picks the engine
via an `engine` param (`google` | `duckduckgo` | `qwant`); the plugin normalizes
an unknown/missing value to a default. Each engine resolves the SERP to a text
result:

- **Google IFL** (`btnI=1`) — fast path to a top pick; on a miss/app-gate/thin
  result, falls back to walking the regular SERP's absolute `http(s)` anchors.
- **DuckDuckGo** — `html.duckduckgo.com/html/?q=…` HTML endpoint, anchor walk.
- **Qwant** — v3 API, with a DataDome challenge shell fallback path.

App/gateway walls (Facebook, app-store deep links, login gates) are filtered out
so the observation is real article text, not a bot wall.

### `browser_fetch`
Fetch a single URL and return its text. Fast path is plain HTTP via OkHttp +
HTML→text via jsoup; fallback is a hidden OS `WebView` render (`android.webkit`,
no extra dependency) for pages that need JavaScript. Fetch + render are capped to
stay under the host's invoke timeout.

## Build

Flutter plugin-app (it is a Flutter application, not a shared Flutter package).
The Gradle wrapper is committed.

```bash
flutter pub get
flutter build apk --debug          # debug build, .debug applicationId suffix

# Local unit tests (no device needed):
cd android && ./gradlew :app:testDebugUnitTest
```

A fresh clone creates `android/local.properties` automatically via `flutter pub
get` / the Flutter tool — it is gitignored and not shipped.

## Dependencies

| Dependency | Version | License |
|---|---|---|
| [OkHttp](https://square.github.io/okhttp/) | 4.12.0 | Apache-2.0 |
| [jsoup](https://jsoup.org/) | 1.18.1 | MIT |

Both are license-clean for redistribution in an APK (no GPL / copyleft).

## License

Licensed under the **Apache License, Version 2.0** — see [LICENSE](LICENSE).

The Kenosis AI host application is distributed separately and is not covered by
this repository's license. This plugin is the open-sourced network component.