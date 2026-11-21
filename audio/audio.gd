extends Node
class_name GameAudio

# Procedurally generated sound effects and a music loop.
# No external audio files: every sound is synthesized into an AudioStreamWAV.

const MIX_RATE := 22050

# Phase 6: real music tracks (Kevin MacLeod, CC BY 4.0 - attribution
# in GameData.MUSIC_CREDITS, shown in the settings screen). The menu
# track loops cleanly; the battle track restarts loud, so its loop
# restart is crossfaded between two players (see _process).
const MENU_TRACK: AudioStream = preload("res://gen_assets_v3/music/menu_at_rest.ogg")
const BATTLE_TRACK: AudioStream = preload("res://gen_assets_v3/music/battle_five_armies.ogg")
const XFADE_SECONDS := 1.5 # battle loop-restart crossfade window
const XFADE_START_BEFORE_END := 2.0 # start the next loop this far before the end

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _music_player: AudioStreamPlayer
var _music_xfade: AudioStreamPlayer # second player: battle loop crossfade
var _jet_player: AudioStreamPlayer
var sfx_volume: float = 0.8
var music_volume: float = 0.5
var music_enabled: bool = true
var sfx_enabled: bool = true # QA-128: SFX mute toggle (settings); true = sounds on
var _current_track: String = "" # "" | "menu" | "battle" | "procedural"
var _last_track: String = "" # remembered across a music on/off toggle
var _xfade_t: float = -1.0 # >= 0 while a battle crossfade is running
var _xfade_from: AudioStreamPlayer
var _xfade_to: AudioStreamPlayer


func _ready() -> void:
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_music_player = AudioStreamPlayer.new()
	add_child(_music_player)
	_music_xfade = AudioStreamPlayer.new()
	add_child(_music_xfade)
	_jet_player = AudioStreamPlayer.new()
	add_child(_jet_player)
	_build_streams()
	# No autostart: the scene that owns this node picks its track
	# (menu -> play_menu_music, match -> play_battle_music), so music
	# can never overlap or keep playing after a scene change.
	# The procedural loop below is only a fallback if an OGG is missing.


func _process(_delta: float) -> void:
	_update_battle_xfade(_delta)


func _build_streams() -> void:
	_streams["shoot"] = _make_noise_burst(0.09, 0.9, 2400.0)
	_streams["pistol"] = _make_noise_burst(0.07, 0.8, 2000.0) # short crack, distinct from the rifle
	_streams["smg"] = _make_noise_burst(0.06, 0.7, 3000.0)
	_streams["shotgun"] = _make_noise_burst(0.22, 1.0, 1200.0)
	_streams["sniper"] = _make_noise_burst(0.28, 1.0, 800.0)
	_streams["rocket"] = _make_noise_burst(0.3, 0.9, 600.0)
	_streams["explosion"] = _make_noise_burst(0.7, 1.0, 300.0)
	_streams["reload"] = _make_clicks([0.0, 0.12], 1800.0)
	_streams["jump"] = _make_sweep(180.0, 420.0, 0.16, 0.6)
	_streams["hit"] = _make_tone(220.0, 0.08, 0.7, 0)
	_streams["hurt"] = _make_tone(140.0, 0.15, 0.8, 0)
	_streams["death"] = _make_sweep(320.0, 70.0, 0.45, 0.8)
	_streams["click"] = _make_tone(660.0, 0.05, 0.5, 0)
	_streams["pickup"] = _make_sweep(440.0, 880.0, 0.18, 0.6)
	_streams["spawn"] = _make_sweep(220.0, 660.0, 0.25, 0.6)
	_streams["jetpack"] = _make_noise_loop(1.0, 0.35, 900.0)
	_streams["win"] = _make_melody([523.0, 659.0, 784.0, 1047.0], 0.16)
	# QA-128 (v3.11): first SFX pass - power-up pickup / activation
	# sounds and hazard sounds. All synthesized in code (no audio
	# files, no licensing risk - the music OGGs stay the only
	# external audio, Kevin MacLeod CC BY 4.0). Volumes stay <= 0.8
	# so SFX never drowns the music (music plays at volume * 0.5).
	_streams["shield"] = _make_hum(0.9, 0.6) # energy hum, detuned sines
	_streams["speed"] = _make_noise_sweep(0.35, 0.7, 300.0, 3200.0) # whoosh up
	_streams["heal"] = _make_melody([880.0, 1174.7], 0.14) # soft two-note chime
	_streams["jetpack_boost"] = _make_noise_sweep(0.5, 0.7, 400.0, 2600.0) # fuel rush
	_streams["wind"] = _make_gust(0.7, 0.8) # wind blast gust
	_streams["thunder"] = _make_thunder() # crack + low rumble
	_streams["invis"] = _make_shimmer(0.6, 0.5) # shimmer glissando
	_streams["tap"] = _make_tone(880.0, 0.04, 0.5, 0) # slot-button tap
	_streams["fire_burn"] = _make_noise_burst(0.4, 0.6, 2500.0) # fire crackle/hiss
	_streams["storm"] = _make_rumble(1.5, 0.5) # storm rumble
	_streams["rock_impact"] = _make_thud(0.3, 0.9) # falling-rock thud


func play(sound_name: String) -> void:
	if not sfx_enabled:
		return
	if not _streams.has(sound_name):
		return
	var stream: AudioStreamWAV = _streams[sound_name]
	for p in _players:
		if not p.playing:
			p.stream = stream
			p.volume_db = linear_to_db(maxf(sfx_volume, 0.001))
			p.play()
			return
	# All busy: reuse the first one.
	_players[0].stream = stream
	_players[0].volume_db = linear_to_db(maxf(sfx_volume, 0.001))
	_players[0].play()


func set_volumes(sfx: float, music: float) -> void:
	sfx_volume = sfx
	music_volume = music
	_apply_music_volume()


func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	if not enabled:
		# Remember the track so re-enabling resumes it.
		_last_track = _current_track
		_stop_all_music()
	elif _last_track != "":
		_play_track(_last_track)
		_last_track = ""


# QA-128: SFX mute. Stops any playing SFX at once; play() no-ops
# while muted. The settings UI toggle (game.gd step) calls this
# next to set_music_enabled; the persisted value lives in
# GameData.sfx_enabled.
func set_sfx_enabled(enabled: bool) -> void:
	sfx_enabled = enabled
	if not enabled:
		for p in _players:
			p.stop()
		_jet_player.stop()


func current_track() -> String:
	return _current_track


func is_music_playing() -> bool:
	return _music_player.playing or _music_xfade.playing


func play_menu_music() -> void:
	_play_track("menu")


func play_battle_music() -> void:
	_play_track("battle")


func stop_music() -> void:
	_last_track = ""
	_stop_all_music()


func _stop_all_music() -> void:
	_current_track = ""
	_xfade_t = -1.0
	_music_player.stop()
	_music_xfade.stop()


func _apply_music_volume() -> void:
	var db := linear_to_db(maxf(music_volume * 0.5, 0.001)) if music_enabled else -80.0
	# During a battle crossfade the two players are volume-driven by
	# _update_battle_xfade; outside it both sit at the target volume
	# (the idle one is stopped, so its volume is irrelevant).
	if _xfade_t < 0.0:
		_music_player.volume_db = db
		_music_xfade.volume_db = db


func _play_track(track: String) -> void:
	if not music_enabled:
		_last_track = track
		return
	if _current_track == track and is_music_playing():
		return
	_stop_all_music()
	_current_track = track
	var stream: AudioStream = null
	if track == "menu":
		stream = MENU_TRACK
	elif track == "battle":
		stream = BATTLE_TRACK
	if stream == null:
		# Fallback: the old procedural loop (never expected - the
		# OGGs ship in the APK - but the game must never go silent
		# because a file failed to load).
		_current_track = "procedural"
		_music_player.stream = _make_music_loop()
		_music_player.volume_db = linear_to_db(maxf(music_volume * 0.5, 0.001))
		_music_player.play()
		return
	if stream is AudioStreamOggVorbis:
		# Godot 4.7 OGG looping is a bool + offset (no loop_mode).
		# The menu track fades in/out cleanly so the restart is
		# inaudible; the battle track is crossfaded by
		# _update_battle_xfade instead of relying on this loop.
		stream.loop = true
		stream.loop_offset = 0.0
	_music_player.stream = stream
	_music_player.volume_db = linear_to_db(maxf(music_volume * 0.5, 0.001))
	_music_player.play()


func _update_battle_xfade(delta: float) -> void:
	if _current_track != "battle":
		return
	if _xfade_t >= 0.0:
		# A crossfade is running: fade the old player out and the new
		# one in over XFADE_SECONDS, then stop the old one.
		_xfade_t += delta
		var f := clampf(_xfade_t / XFADE_SECONDS, 0.0, 1.0)
		var target_db := linear_to_db(maxf(music_volume * 0.5, 0.001))
		if _xfade_from != null:
			_xfade_from.volume_db = lerpf(target_db, -80.0, f)
		if _xfade_to != null:
			_xfade_to.volume_db = lerpf(-80.0, target_db, f)
		if f >= 1.0:
			if _xfade_from != null:
				_xfade_from.stop()
			# The faded-in player becomes the main one.
			if _xfade_to == _music_xfade:
				var tmp := _music_player
				_music_player = _music_xfade
				_music_xfade = tmp
			_xfade_t = -1.0
			_apply_music_volume()
		return
	# Start the next loop early: when the active player is about to
	# hit the loud restart, begin the same track on the idle player
	# at silence and crossfade into it.
	var active := _music_player
	if not active.playing or active.stream == null:
		return
	var remain := active.stream.get_length() - active.get_playback_position()
	if remain <= XFADE_START_BEFORE_END and remain > 0.0:
		var idle := _music_xfade
		idle.stream = active.stream
		idle.volume_db = -80.0
		idle.play()
		_xfade_from = active
		_xfade_to = idle
		_xfade_t = 0.0


func start_jetpack() -> void:
	if _jet_player.playing:
		return
	_jet_player.stream = _streams["jetpack"]
	_jet_player.volume_db = linear_to_db(maxf(sfx_volume * 0.5, 0.001))
	_jet_player.play()


func stop_jetpack() -> void:
	_jet_player.stop()


# --- Synthesis helpers ---

func _pack_samples(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


func _make_tone(freq: float, dur: float, vol: float, _unused: int) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := 1.0 - float(i) / n
		samples[i] = sin(TAU * freq * t) * vol * env
	return _pack_samples(samples)


func _make_sweep(f0: float, f1: float, dur: float, vol: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var phase := 0.0
	for i in n:
		var frac := float(i) / n
		var freq := lerpf(f0, f1, frac)
		phase += TAU * freq / MIX_RATE
		var env := 1.0 - frac * 0.8
		samples[i] = sin(phase) * vol * env
	return _pack_samples(samples)


func _make_noise_burst(dur: float, vol: float, cutoff: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var last := 0.0
	var alpha := clampf(cutoff / MIX_RATE, 0.01, 1.0)
	for i in n:
		var frac := float(i) / n
		var env := (1.0 - frac) * (1.0 - frac)
		var white := randf() * 2.0 - 1.0
		last += alpha * (white - last)
		samples[i] = last * vol * env * 2.0
	return _pack_samples(samples)


func _make_noise_loop(dur: float, vol: float, cutoff: float) -> AudioStreamWAV:
	var wav := _make_noise_burst(dur, vol, cutoff)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = int(MIX_RATE * dur)
	return wav


# QA-128: filtered noise whose lowpass cutoff rises - a whoosh /
# rush (speed boost, jetpack boost fuel rush). Swells in and out.
func _make_noise_sweep(dur: float, vol: float, cutoff0: float, cutoff1: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var last := 0.0
	for i in n:
		var frac := float(i) / n
		var cutoff := lerpf(cutoff0, cutoff1, frac)
		var alpha := clampf(cutoff / MIX_RATE, 0.01, 1.0)
		var env := sin(PI * frac)
		var white := randf() * 2.0 - 1.0
		last += alpha * (white - last)
		samples[i] = last * vol * env * 2.0
	return _pack_samples(samples)


# QA-128: wind gust - low filtered noise with a slow swell and a
# 7 Hz tremble, so it reads as a gust rather than steady hiss.
func _make_gust(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var last := 0.0
	for i in n:
		var frac := float(i) / n
		var env := sin(PI * frac)
		var wobble := 0.7 + 0.3 * sin(TAU * 7.0 * float(i) / MIX_RATE)
		var white := randf() * 2.0 - 1.0
		last += 0.08 * (white - last)
		samples[i] = last * vol * env * wobble * 3.0
	return _pack_samples(samples)


# QA-128: thunder - a loud short low crack, then a 60 Hz rumble
# decaying over 1.2 s. Used by the Thunder Strike power-up and by
# the summit lightning hazard (same sound, one stream).
func _make_thunder() -> AudioStreamWAV:
	var dur := 1.2
	var n := int(MIX_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var last := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var crack_env := exp(-t * 22.0)
		var white := randf() * 2.0 - 1.0
		last += 0.05 * (white - last)
		var crack := last * crack_env * 2.2
		phase += TAU * 60.0 / MIX_RATE
		var rumble := sin(phase) * exp(-t * 3.0) * 0.7
		samples[i] = (crack + rumble) * 0.8
	return _pack_samples(samples)


# QA-128: invisibility shimmer - a high sine gliding down
# (1600 -> 550 Hz) with an 18 Hz tremolo. Quiet by design.
func _make_shimmer(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var phase := 0.0
	for i in n:
		var frac := float(i) / n
		var freq := lerpf(1600.0, 550.0, frac)
		phase += TAU * freq / MIX_RATE
		var env := sin(PI * frac)
		var trem := 0.6 + 0.4 * sin(TAU * 18.0 * float(i) / MIX_RATE)
		samples[i] = sin(phase) * vol * env * trem
	return _pack_samples(samples)


# QA-128: shield hum - two detuned sines (110 + 116.5 Hz) beating
# softly against each other, fading in fast and out slowly.
func _make_hum(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var frac := float(i) / n
		var env := minf(frac * 8.0, 1.0) * (1.0 - frac * 0.5)
		samples[i] = (sin(TAU * 110.0 * t) + sin(TAU * 116.5 * t)) * 0.5 * vol * env
	return _pack_samples(samples)


# QA-128: storm rumble - very low filtered noise swelling slowly.
func _make_rumble(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var last := 0.0
	for i in n:
		var frac := float(i) / n
		var env := sin(PI * frac)
		var white := randf() * 2.0 - 1.0
		last += 0.03 * (white - last)
		samples[i] = last * vol * env * 3.0
	return _pack_samples(samples)


# QA-128: impact thud - a 70 Hz sine decay plus a short noise
# burst, for falling rocks landing.
func _make_thud(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var last := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var frac := float(i) / n
		phase += TAU * 70.0 / MIX_RATE
		var thump := sin(phase) * exp(-t * 14.0)
		var white := randf() * 2.0 - 1.0
		last += 0.2 * (white - last)
		var burst := last * exp(-t * 30.0) * 0.8
		samples[i] = (thump + burst) * vol
	return _pack_samples(samples)


func _make_clicks(times: Array, freq: float) -> AudioStreamWAV:
	var dur := 0.3
	var n := int(MIX_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for t in times:
		var start := int(float(t) * MIX_RATE)
		for i in range(0, int(0.03 * MIX_RATE)):
			if start + i < n:
				samples[start + i] += sin(TAU * freq * float(i) / MIX_RATE) * 0.8 * (1.0 - float(i) / (0.03 * MIX_RATE))
	return _pack_samples(samples)


func _make_melody(notes: Array, note_dur: float) -> AudioStreamWAV:
	var total := int(MIX_RATE * note_dur * notes.size())
	var samples := PackedFloat32Array()
	samples.resize(total)
	for ni in notes.size():
		var freq: float = notes[ni]
		var start := int(ni * note_dur * MIX_RATE)
		var nn := int(note_dur * MIX_RATE)
		for i in nn:
			var t := float(i) / MIX_RATE
			var env := 1.0 - float(i) / nn * 0.7
			samples[start + i] += sin(TAU * freq * t) * 0.5 * env
	return _pack_samples(samples)


func _make_music_loop() -> AudioStreamWAV:
	# 8-second loop: simple bass line + sparse lead, quiet by design.
	var dur := 8.0
	var n := int(MIX_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var bass_notes := [110.0, 110.0, 130.8, 98.0, 110.0, 110.0, 146.8, 130.8]
	var lead_notes := [440.0, 0.0, 523.0, 0.0, 659.0, 0.0, 587.0, 523.0]
	var step := dur / 8.0
	for s in 8:
		var start := int(s * step * MIX_RATE)
		var nn := int(step * MIX_RATE)
		var bf: float = bass_notes[s]
		for i in nn:
			var t := float(i) / MIX_RATE
			var env := 1.0 - float(i) / nn * 0.6
			samples[start + i] += sin(TAU * bf * t) * 0.28 * env
			samples[start + i] += sin(TAU * bf * 0.5 * t) * 0.12 * env
		var lf: float = lead_notes[s]
		if lf > 0.0:
			for i in nn:
				var t := float(i) / MIX_RATE
				var env := 1.0 - float(i) / nn * 0.8
				samples[start + i] += sin(TAU * lf * t) * 0.12 * env
	var wav := _pack_samples(samples)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav
