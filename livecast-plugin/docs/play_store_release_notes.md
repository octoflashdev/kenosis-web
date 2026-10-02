# Play Store Release Notes — LiveCast plugin

Per-version release notes for the plugin's own Play Console package.
Same rules as the host file: each `## <version>` section is the upload's
"What's new" (max 500 chars); versions match THIS app's pubspec
(`plugins/livecast/pubspec.yaml`), not the host's. The release-notes-leak
guard scans this file for this app's current version.

## 0.1.1+2

Shell upgrade: a navigation drawer with light/dark/auto theme, About, Privacy Notice, App permissions and open-source licenses. "Get Kenosis AI" opens the main app's Play Store page, always behind a confirmation alert; the About screen links this plugin's own source tree. Unchanged under the hood: the live transcript page is served only to devices on your own Wi-Fi — nothing is sent to the app maker or any third party.
