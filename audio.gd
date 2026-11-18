extends Node
class_name GameAudio

# Procedurally generated sound effects and a music loop.
# No external audio files: every sound is synthesized into an AudioStreamWAV.

const MIX_RATE := 22050

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _music_player: AudioStreamPlayer
var _jet_player: AudioStreamPlayer
var sfx_volume: float = 0.8
var music_volume: float = 0.5


func _ready() -> void:
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_music_player = AudioStreamPlayer.new()
	add_child(_music_player)
	_jet_player = AudioStreamPlayer.new()
	add_child(_jet_player)
	_build_streams()
	_start_music()


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


func play(sound_name: String) -> void:
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
	if _music_player != null:
		_music_player.volume_db = linear_to_db(maxf(music_volume * 0.5, 0.001))


func start_jetpack() -> void:
	if _jet_player.playing:
		return
	_jet_player.stream = _streams["jetpack"]
	_jet_player.volume_db = linear_to_db(maxf(sfx_volume * 0.5, 0.001))
	_jet_player.play()


func stop_jetpack() -> void:
	_jet_player.stop()


func _start_music() -> void:
	var music := _make_music_loop()
	_music_player.stream = music
	_music_player.volume_db = linear_to_db(maxf(music_volume * 0.5, 0.001))
	_music_player.play()


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
