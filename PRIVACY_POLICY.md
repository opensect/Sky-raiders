# Privacy Policy — LAN Arena Shooter

**Last updated: 19 November 2026 — version 3.2**

LAN Arena Shooter is a local-multiplayer arena game. It is played
entirely on your own Wi-Fi network (LAN). This policy explains what
the app does and does not do with your information.

## What the app collects: nothing

- **No personal data is collected, stored, shared, or sold.** There
  are no accounts, no sign-in, no email, no phone number, no name
  collection, and no contact access.
- **No analytics, no tracking, no advertising.** The app contains no
  analytics SDK, no ad SDK, no crash-reporting SDK, and no third-party
  tracker of any kind.
- **No internet connection is used.** Phones talk directly to each
  other over your local Wi-Fi network (or a phone hotspot) using
  standard local-network sockets (UDP broadcast for room discovery,
  ENet/UDP for gameplay). No game data is sent to the internet or to
  any server. There is no server: one phone hosts, the others join it.

## What stays on your phone

- **Game settings only:** your display name, colour/helmet choice,
  control sensitivity, volume, and music settings. These are stored
  locally on your own phone (Godot user settings) and are never
  uploaded anywhere.
- **Your display name** is shown to the other players in the same
  room so they can tell players apart. It is sent only to the phones
  in that room, over your local Wi-Fi, and only while you are playing.

## Permissions

The app requests only these Android permissions, all needed for local
multiplayer:

| Permission | Why |
|---|---|
| `INTERNET` | Required by Android for any app that opens network sockets — here, only local Wi-Fi sockets to the other phones in the room. |
| `ACCESS_NETWORK_STATE` | To check that Wi-Fi is available before hosting or joining. |
| `ACCESS_WIFI_STATE` | To read the phone's own Wi-Fi address so the host can show it and joiners can type it. |

No location permission, no Bluetooth permission, no storage,
camera, microphone, or contacts permission is requested. None of the
three permissions above is a runtime ("dangerous") permission on
Android — all are granted automatically at install, so the app never
shows a permission pop-up.

## Children

The app is a general-audience game with no data collection and no
communication with strangers: players can only join people on the
same Wi-Fi network. It is safe for all ages in that respect, and the
Google Play content rating should be completed as "Everyone".

## Changes

If this policy ever changes (for example, if an online feature is
added), the updated policy will be shown in the app's Settings screen
and in this file before the change takes effect.

## Contact

This is an independent hobby project. There is no company, no support
email, and no data controller to contact — because there is no data.
