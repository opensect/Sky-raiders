# Music licences — LAN Arena Shooter (Godot)

Two royalty-free music tracks, both by Kevin MacLeod, downloaded from the
official Incompetech site and re-encoded to OGG Vorbis for Godot.
No game code was changed; these are new files only.

## Licence (applies to both tracks)

**Creative Commons Attribution 4.0 International (CC BY 4.0)**
https://creativecommons.org/licenses/by/4.0/

Confirmed on Incompetech's own FAQ page
(https://incompetech.com/music/royalty-free/faq.html):
"Creative Commons: By Attribution 4.0" — all of the site's music is offered
under this licence. Free to use in commercial and non-commercial projects,
including games, provided the attribution below is given.

**Attribution must appear in the game** (credits screen / settings screen
is enough). Use the exact text given per track below.

---

## 1. MENU track — `menu_at_rest.ogg`

- **Track:** "At Rest" — Kevin MacLeod (incompetech.com)
- **Mood:** calm, atmospheric, slow piano / strings / choir — menu music
- **Source page:** https://incompetech.com/music/royalty-free/
- **Direct file URL (verified 200 from incompetech.com, 2026-11-19):**
  https://incompetech.com/music/royalty-free/mp3-royaltyfree/At%20Rest.mp3
- **Licence:** CC BY 4.0 — https://creativecommons.org/licenses/by/4.0/
- **Attribution (exact text to show in-game):**
  > "At Rest" Kevin MacLeod (incompetech.com)
  > Licensed under Creative Commons: By Attribution 4.0 License
  > http://creativecommons.org/licenses/by/4.0/
- **Shipped file:** OGG Vorbis, stereo, 48 kHz, ~96 kbps (q2)
- **Duration:** 3:26.6 (206.6 s) — slightly over the 1–3 min target, kept whole
  so the fade-in/fade-out stays intact
- **Size:** 2,195,865 bytes (~2.1 MB)
- **MD5:** 00298b2e64a3ed589998588bdb464098
- **Decode check:** `ffmpeg -v error -i menu_at_rest.ogg -f null -` — zero errors
- **Loop check:** LOOPS CLEANLY. Fades in from silence (first 0.1 s at
  −91 dB) and fades out to silence (last 1 s peak −56.5 dB, last 0.1 s
  −91 dB). Restarting the track in Godot produces no click or jump.

## 2. BATTLE track — `battle_five_armies.ogg`

- **Track:** "Five Armies" — Kevin MacLeod (incompetech.com)
- **Mood:** energetic, driving epic orchestral battle music
- **Source page:** https://incompetech.com/music/royalty-free/
- **Direct file URL (verified 200 from incompetech.com, 2026-11-19):**
  https://incompetech.com/music/royalty-free/mp3-royaltyfree/Five%20Armies.mp3
- **Licence:** CC BY 4.0 — https://creativecommons.org/licenses/by/4.0/
- **Attribution (exact text to show in-game):**
  > "Five Armies" Kevin MacLeod (incompetech.com)
  > Licensed under Creative Commons: By Attribution 4.0 License
  > http://creativecommons.org/licenses/by/4.0/
- **Shipped file:** OGG Vorbis, stereo, 44.1 kHz, ~128 kbps (q4)
- **Duration:** 2:35.8 (155.8 s)
- **Size:** 2,403,963 bytes (~2.3 MB)
- **MD5:** e5b74d15a15d960bc0ed08f9b90fe9eb
- **Decode check:** `ffmpeg -v error -i battle_five_armies.ogg -f null -` — zero errors
- **Loop check:** NOT SEAMLESS — audible restart jump. The track fades out
  cleanly to silence (last 1 s peak −114 dB, last 3 s mean −66.4 dB) but
  restarts loud with a driving orchestral hit (first 3 s mean −23.9 dB,
  max −7.7 dB). No click/pop at the seam, but the music restarting is
  noticeable. If the game supports it, use a short crossfade on loop
  restart; otherwise accept the restart as-is — it sounds like the track
  starting again, not a glitch.

---

## Sources tried and rejected (for the record)

- **Pixabay Music — BLOCKED, not used.** pixabay.com returned HTTP 403
  (Cloudflare) to curl and is blocked by policy for page fetches, so no
  Pixabay track or licence could be verified. No Pixabay audio downloaded.
- **FreePD (freepd.com) — CLOSED, not used.** The site now serves only a
  "Site Closed / 2008–2025" notice. The only remaining copies are an
  anonymous archive.org mirror with no licence metadata, so no FreePD
  track's licence could be verified on its own page. Not used.
- **Incompetech candidates checked but not shipped:** "Almost in F"
  (32 min 42 s, 78 MB — far too long), "Killers" (5:05 — too long),
  "Meditation Impromptu 01" (3:33), "Lobby Time" (3:13, jazzy — wrong
  mood for a military menu), "Volatile Reaction" (2:45, usable battle
  alternative). All are the same CC BY 4.0 Kevin MacLeod catalogue.

## Re-encoding note

Originals are 320 kbps MP3s from incompetech.com. They were re-encoded
with `ffmpeg -c:a libvorbis` (menu q2, battle q4) to stay under ~3 MB
each for the APK. No audio content was cut or altered.
