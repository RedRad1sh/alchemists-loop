extends Node
# Весь звук — процедурный, ни одного аудиофайла.
# SFX: синтез осцилляторов в WAV при старте. Музыка: мягкий эмбиент-луп (Am–F–C–G).

const SR := 22050
const TAU := 6.283185307

var music_on := true
var sfx_volume := 1.0   # 0..1, мастер-громкость эффектов
var music_volume := 1.0 # 0..1, громкость эмбиента
var _music_player: AudioStreamPlayer
var _players: Array[AudioStreamPlayer] = []
var _rr := 0

func _ready() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.volume_db = -10.0
		add_child(p)
		_players.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = 0.0 + linear_to_db(maxf(music_volume, 0.001))
	add_child(_music_player)
	_music_player.stream = _build_music()
	if music_on:
		_music_player.play()

# ---------- низкоуровневый синтез ----------

func _make_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 30000.0)
		bytes.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	w.data = bytes
	return w

func _tone(freq: float, dur: float, vol: float = 0.4, warm: bool = true) -> PackedFloat32Array:
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / SR
		var env: float = 1.0 / (1.0 + 7.0 * t / dur)
		var v: float = sin(TAU * freq * t)
		if warm:
			v += 0.35 * sin(TAU * freq * 2.0 * t) + 0.12 * sin(TAU * freq * 3.0 * t)
		out[i] = v * env * vol
	return out

func _sweep(f0: float, f1: float, dur: float, vol: float = 0.4) -> PackedFloat32Array:
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / SR
		var f: float = lerpf(f0, f1, t / dur)
		ph += TAU * f / SR
		var env: float = 1.0 / (1.0 + 6.0 * t / dur)
		out[i] = sin(ph) * env * vol
	return out

func _puff(dur: float, vol: float = 0.25) -> PackedFloat32Array:
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	var r := RandomNumberGenerator.new()
	for i in n:
		var t := float(i) / SR
		last = last * 0.82 + (r.randf() * 2.0 - 1.0) * 0.18
		var env: float = 1.0 / (1.0 + 9.0 * t / dur)
		out[i] = last * env * vol
	return out

func _mix(parts: Array) -> PackedFloat32Array:
	var total := 0
	for p in parts:
		total = maxi(total, p.size())
	var out := PackedFloat32Array()
	out.resize(total)
	for p in parts:
		for i in p.size():
			out[i] += p[i]
	return out

func _play(samples: PackedFloat32Array, vol_db: float = 0.0) -> void:
	var p := _players[_rr]
	_rr = (_rr + 1) % _players.size()
	p.volume_db = vol_db + linear_to_db(maxf(sfx_volume, 0.001))
	p.stream = _make_wav(samples)
	p.play()

# ---------- публичные звуки ----------

func bubble() -> void:
	_play(_sweep(randf_range(300.0, 640.0), randf_range(160.0, 320.0), 0.08, 0.5))

func click() -> void:
	_play(_tone(1250.0, 0.035, 0.18, false))

func divide() -> void:
	var a := _sweep(220.0, 520.0, 0.22, 0.5)
	var b := _tone(660.0, 0.25, 0.35)
	_play(_mix([a, b]))

func morph() -> void:
	_play(_sweep(300.0, 900.0, 0.5, 0.3))

func draft_open() -> void:
	_play(_mix([_tone(440.0, 0.16, 0.22), _tone(660.0, 0.2, 0.18)]))

func legendary() -> void:
	var parts: Array = []
	for f in [523.0, 659.0, 784.0, 1046.0]:
		parts.append(_tone(f, 0.28, 0.2))
	_play(_mix(parts), -2.0)


func discovery() -> void:
	# тихий звон открытия вещества/рецепта: два «колокольчика»
	var a := _bell(784.0, 0.8, 0.12)
	var b := _bell(1174.7, 1.0, 0.09)
	_play(_mix([a, b]), -3.0)


func mystic() -> void:
	# мистический звук события мира: восходящее сияние + мерцание высоких
	var rise := _sweep(330.0, 990.0, 1.4, 0.10)
	var shimmer := _shimmer()
	_play(_mix([rise, shimmer]), -2.0)


func _bell(freq: float, dur: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / SR
		var env: float = pow(maxf(1.0 - t / dur, 0.0), 2.2)
		var v: float = sin(TAU * freq * t)
		v += 0.5 * sin(TAU * freq * 2.0 * t) * (1.0 - t / dur)
		v += 0.2 * sin(TAU * freq * 2.99 * t) * (1.0 - t / dur)
		out[i] = v * env * vol
	return out


func _shimmer() -> PackedFloat32Array:
	var dur := 1.6
	var n := int(dur * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / SR
		var trem := 0.5 + 0.5 * sin(TAU * 5.0 * t)
		var v: float = sin(TAU * 1318.5 * t) * 0.6
		v += sin(TAU * 1975.5 * t) * 0.4
		out[i] = v * trem * 0.08 * minf(t / 0.4, 1.0)
	return out

func stage_up() -> void:
	var parts: Array = []
	for f in [392.0, 523.0, 659.0]:
		parts.append(_tone(f, 0.24, 0.22))
	_play(_mix(parts), -2.0)

func pet() -> void:
	_play(_sweep(700.0, 1400.0, 0.12, 0.3))

func error() -> void:
	_play(_tone(170.0, 0.14, 0.3, false))

# ---------- фоновая музыка (эмбиент, Am–F–C–G) ----------

func _build_music() -> AudioStreamWAV:
	var secs := 16.0
	var n := int(secs * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var chords := [
		[110.0, 130.81, 164.81],   # A2 C3 E3 (Am)
		[87.31, 110.0, 130.81],    # F2 A2 C3 (F)
		[130.81, 164.81, 196.0],   # C3 E3 G3 (C)
		[98.0, 123.47, 146.83]     # G2 B2 D3 (G)
	]
	var chord_len := int(secs / 4.0 * SR)
	for ci in 4:
		var freqs: Array = chords[ci]
		for i in chord_len:
			var t := float(i) / SR
			var seg := float(i) / float(chord_len)
			var env: float = minf(seg * 6.0, 1.0) * minf((1.0 - seg) * 6.0 + 0.15, 1.0)
			env = maxf(env, 0.0)
			var v := 0.0
			for f in freqs:
				v += sin(TAU * f * t) * 0.55
				v += sin(TAU * f * 2.0 * t) * 0.12
			out[ci * chord_len + i] = v * env * 0.18
	return _make_wav(out, true)

func toggle_music() -> bool:
	music_on = not music_on
	if music_on:
		_music_player.play()
	else:
		_music_player.stop()
	return music_on

func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)

func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_music_player.volume_db = 0.0 + linear_to_db(maxf(music_volume, 0.001))
