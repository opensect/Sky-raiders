# Google Play submission checklist — LAN Arena Shooter

**Status (19 Nov 2026, v3.2): the app is Play-ready in code and
policy. NOTHING has been published or submitted — there is no Play
Console account connected here, and publishing needs the user's own
account. This file is the handoff for that step.**

## Already done in v3.2 (verify again at export time)

- [x] **Target API:** targetSdk **36** (verified on the v3.1 APK with
  `aapt2 dump badging`: `targetSdkVersion:'36'`, minSdk 24,
  compileSdk 36). Play requires target API 35+ (Aug 2025 rule);
  36 exceeds it. Re-verify on the v3.2 APK/AAB with the same command.
- [x] **64-bit:** arm64-v8a only (`native-code: 'arm64-v8a'` in the
  aapt2 dump). Play requires 64-bit — satisfied.
- [x] **Only necessary permissions:** exactly three, all networking,
  all install-time ("normal") permissions — `INTERNET`,
  `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`. No location,
  Bluetooth, storage, camera, microphone, or contacts permission.
  Verified with `aapt2 dump badging` (v3.1 APK) — re-verify on v3.2.
- [x] **No personal data collected or shared:** no accounts, no
  sign-in, no ads, no analytics, no tracking SDKs (verified by code
  search, 19 Nov 2026). Gameplay is LAN-only (UDP broadcast +
  ENet/UDP between phones on the same Wi-Fi); nothing goes to the
  internet or any server.
- [x] **Privacy policy written:** `PRIVACY_POLICY.md` in the project
  root (full text) + the same short text in-app in **Settings →
  Privacy**, + a permissions explanation in **Multiplayer** ("Internet
  + network state only…"). The policy URL for the Play listing must
  point at a hosted copy of `PRIVACY_POLICY.md` (e.g. a GitHub repo
  page) — Play does not accept a local file.
- [x] **Versioning:** v3.2 / versionCode **10** (final export worker:
  set `version/code=10` and `version/name="3.2"` in
  `export_presets.cfg`; `GameData.BUILD_VERSION` is already `"3.2"`).
- [x] **Android compliance for multiplayer:** plain UDP/ENet sockets
  need only the three permissions above at targetSdk 36. No runtime
  permission request is required (none of the three is a runtime
  permission), so no pop-up flow was added — adding one would be
  wrong. Discovery uses UDP **broadcast** (255.255.255.255 / subnet
  broadcast), not IP multicast, so no `MulticastLock` /
  `CHANGE_WIFI_MULTICAST_STATE` is needed. No background service:
  the game only networks while in the foreground. Note for the
  future: Android 17 (API 37) gates LAN access behind a new runtime
  permission (`ACCESS_LOCAL_NETWORK`) — that applies only to apps
  targeting API 37+, so do NOT add it while targeting 36.

## Still to do at export time (final export worker)

- [ ] **Build the AAB, not just the APK.** In Godot: enable the
  Gradle build for the Android preset (or use the `android/` Gradle
  project in this repo) and export **Android App Bundle**. Play
  requires AAB for new apps; the direct-install APK stays as the
  sideload build.
  - **v3.2 export outcome (19 Nov 2026): BLOCKED — no release
    keystore exists.** Worker 3 searched the whole home directory
    for `*.keystore`: only the Godot debug keystore exists. A
    release keystore was NOT created (its password must come from
    the user via Secure Vault — never invented, never written in a
    file). The v3.2 APK (versionCode 10, md5
    `cf1d7392f79bd1ba1f1104e26f18cf26`) is the deliverable; the AAB
    can be built once the user supplies the keystore password, by
    the steps below.
- [ ] **Release signing — DO NOT reuse the debug keystore for the
  AAB.** The direct-install APK must stay on the **same debug
  keystore as v3.1** (cert SHA-256
  `f65f2fa3d8041b5e8920e627355a0dd68d9b50414d6b40702fea6b4da6e02d11`)
  so it installs over v3.1 cleanly. The Play AAB needs its own
  **release keystore**:
  1. Create it with `keytool -genkeypair -keystore
     lan-arena-release.keystore -alias lanarena -keyalg RSA
     -keysize 2048 -validity 10000` (or let Play App Signing generate
     it — recommended: enrol in Play App Signing and let Google hold
     the signing key).
  2. Store the keystore file **outside the repo** (e.g.
     `~/workspace/secure/` or a password manager's file storage —
     never in git, never in chat, never in `MEMORY.md`).
  3. Store its passwords in the **Secure Vault only** (keystore
     password + key password, two separate entries). Never write a
     keystore password in any file, chat message, or memory note.
  4. Record here (in this checklist) only: keystore filename,
     alias, and where the passwords live — never the passwords.
- [ ] **Verify the AAB the same way as the APK:** unzip the AAB (it
  is a zip) and check its `AndroidManifest.xml` / base manifest for
  exactly the three permissions and targetSdk 36; check the AAB
  contains the arm64-v8a native library.

## Still to do on the user's side (Play Console — needs the user)

- [ ] **Play Console account:** create / use a Google Play developer
  account ($25 one-time fee, user's own Google account). No account
  is connected here; nobody here can publish.
- [ ] **App listing:** create the app (package `com.lanarena.shooter`,
  title "LAN Arena Shooter"), upload the signed AAB, fill the store
  listing: short + full description, screenshots (phone + 7" tablet
  minimum), feature graphic 1024×500, app icon 512×512.
- [ ] **Content rating:** complete the rating questionnaire
  (violence: cartoon/fantasy combat — expect **Everyone** or
  **Everyone 10+** depending on answers; no user-generated content,
  no chat, no purchases).
- [ ] **Data safety form:** declare **"No data collected"** and **"No
  data shared"** — matches the privacy policy. Data types: none.
  (If the form forces a data-type choice, the honest answer is that
  the app collects nothing; the display name is shared only with
  other players on the same Wi-Fi during a match and is not
  collected by the developer.)
- [ ] **Privacy policy URL:** host `PRIVACY_POLICY.md` somewhere
  public (e.g. the project's GitHub repo) and paste that URL in the
  store listing + data safety section.
- [ ] **App category:** Games → Action (or Arcade). No in-app
  purchases, no ads — declare both as "No".
- [ ] **Target audience / Families:** not a children's app; no
  Families-policy declarations needed.
- [ ] **Testing track:** upload the AAB to **internal testing** first,
  install on the two real phones, run the two-phone join test
  (README "Testing the join on two real phones"), then promote to
  production.
