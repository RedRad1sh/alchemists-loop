extends Node

const SR := 22050
const TAU := 6.283185307
const UI_DB := -12.0

var music_on := true
var sfx_volume := 1.0
var music_volume := 1.0
var _music_player: AudioStreamPlayer
var _spin_player: AudioStreamPlayer  # зацикленный звук верчения ритуала
var _players: Array[AudioStreamPlayer] = []
var _rr := 0

# --- Центральный конфиг звуков (assets/audio/sounds.json) ---
# Ключ = событие; значение = {file, volume_db, pitch, delay}.
# file (путь к wav/ogg) — если пуст/не найден, играется процедурный fallback.
var _sound_cfg: Dictionary = {}
var _stream_cache: Dictionary = {}
const SOUNDS_CFG_PATH := "res://assets/audio/sounds.json"

func _ready() -> void:
	_load_sound_cfg()
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		_players.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = linear_to_db(maxf(music_volume, 0.001))
	add_child(_music_player)
	_spin_player = AudioStreamPlayer.new()
	_spin_player.volume_db = linear_to_db(maxf(sfx_volume, 0.001))
	add_child(_spin_player)
	# Музыка из конфига: {file, volume_db, pitch, delay} в events.music.
	# Если file задан — грузим (loop); иначе процедурная _build_music().
	var mcfg: Dictionary = _sound_cfg.get("music", {})
	var mfile := str(mcfg.get("file", ""))
	if mfile != "":
		var mst: AudioStream = load(mfile) as AudioStream
		if mst != null:
			if mst is AudioStreamWAV:
				(mst as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			_music_player.stream = mst
			_music_player.volume_db = float(mcfg.get("volume_db", 0.0)) \
				+ linear_to_db(maxf(music_volume, 0.001))
	else:
		_music_player.stream = _build_music()
	if music_on:
		_music_player.play()

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

## Загрузить конфиг звуков из sounds.json.
func _load_sound_cfg() -> void:
	if FileAccess.file_exists(SOUNDS_CFG_PATH):
		var f := FileAccess.open(SOUNDS_CFG_PATH, FileAccess.READ)
		if f != null:
			var txt := f.get_as_text()
			var parsed: Variant = JSON.parse_string(txt)
			if parsed is Dictionary and (parsed as Dictionary).has("events"):
				_sound_cfg = (parsed as Dictionary)["events"] as Dictionary

## ЭКСПЕРИМЕНТ В КОТЛЕ: найдено новое сочетание (попап открытия рецепта).
func brew_discover() -> void:
	if _check_cfg_event("brew_discover"):
		return
	var a := _bell(784.0, 0.8, 0.12)
	var b := _bell(1174.7, 1.0, 0.09)
	_play(_mix([a, b]), -3.0)

## СТАРТ КРАФТА: подтверждение на доске (списание ингредиентов, начало ритуала).
func craft_start() -> void:
	if _check_cfg_event("craft_start"):
		return
	_play_ui(_sweep(260.0, 620.0, 0.3, 0.22))

## ДОСТИЖЕНИЕ: клейм награды комплекта (милстоун Аркана).
func achievement() -> void:
	if _check_cfg_event("achievement"):
		return
	var a := _bell(659.0, 0.5, 0.12)
	var b := _bell(987.8, 0.7, 0.08)
	_play(_mix([a, b]), -4.0)

## ВХОД В ИГРУ: приветственный аккорд при старте (не в selftest).
func game_start() -> void:
	if _check_cfg_event("game_start"):
		return
	var parts: Array = []
	for i in 3:
		parts.append(_tone(220.0 * pow(1.26, i), 0.5, 0.16))
	_play(_mix(parts), -4.0)

## РИТУАЛ: фаза сменилась (призыв/стихии/форма/вспышка).
func ritual_phase() -> void:
	if _check_cfg_event("ritual_phase"):
		return
	_play(_sweep(200.0, 520.0, 0.5, 0.22) if _rng() else _tone(330.0, 0.4, 0.2))

## РИТУАЛ: нажатие руны — тихий короткий отклик.
func ritual_rune() -> void:
	if _check_cfg_event("ritual_rune"):
		return
	_play_ui(_tone(880.0 + randf_range(-60.0, 60.0), 0.06, 0.14, false))

## РИТУАЛ: верчение круга. Файл из конфига, при loop:true — зацикленный
## кусок (start_sec/len_sec), играет пока не вызван ritual_spin_stop().
## Процедурный fallback — одноразовый свип (loop недоступен без конфига).
func ritual_spin() -> void:
	var ev: Dictionary = _sound_cfg.get("ritual_spin", {})
	var file := str(ev.get("file", ""))
	if file == "":
		_play_ui(_sweep(400.0, 1200.0, 0.22, 0.16))
		return
	var stream := _load_event_stream("ritual_spin", file)
	if stream == null:
		_play_ui(_sweep(400.0, 1200.0, 0.22, 0.16))
		return
	_spin_player.stop()
	_spin_player.stream = stream
	_spin_player.volume_db = float(ev.get("volume_db", -10.0)) \
		+ linear_to_db(maxf(sfx_volume, 0.001))
	_spin_player.pitch_scale = float(ev.get("pitch", 1.0))
	_spin_player.play()

## Остановить зацикленное верчение (выход из фазы MATERIALIZE).
func ritual_spin_stop() -> void:
	if _spin_player != null:
		_spin_player.stop()

## РИТУАЛ: карта раскрыта (успех крафта).
func ritual_reveal() -> void:
	if _check_cfg_event("ritual_reveal"):
		return
	var a := _bell(1046.5, 0.6, 0.12)
	var b := _bell(1568.0, 0.8, 0.08)
	_play(_mix([a, b]), -3.0)

func _rng() -> bool:
	return randf() > 0.5

## Воспроизвести событие по имени (из конфига или процедурный fallback).
## Используется из кода для UI/событий/ритуала и из debug-меню прослушивания.
func play_event(event_name: String) -> void:
	var ev: Dictionary = _sound_cfg.get(event_name, {})
	var file := str(ev.get("file", ""))
	if file != "":
		_play_file(event_name, file, float(ev.get("volume_db", 0.0)),
			float(ev.get("pitch", 1.0)), float(ev.get("delay", 0.0)))
		return
	# Процедурный fallback: тот же звук, что генерировался раньше.
	match event_name:
		"bubble": bubble()
		"click": click()
		"divide": divide()
		"morph": morph()
		"draft_open": draft_open()
		"legendary": legendary()
		"discovery": discovery()
		"mystic": mystic()
		"stage_up": stage_up()
		"pet": pet()
		"error": error()
		"ritual_phase": ritual_phase()
		"ritual_rune": ritual_rune()
		"ritual_spin": ritual_spin()
		"ritual_reveal": ritual_reveal()
		"achievement": achievement()
		"game_start": game_start()
		"brew_discover": brew_discover()
		"craft_start": craft_start()

## Загрузить поток события с нарезкой (start_sec/len_sec) и loop.
func _load_event_stream(event_name: String, file: String) -> AudioStream:
	var ev: Dictionary = _sound_cfg.get(event_name, {})
	var start_sec := float(ev.get("start_sec", 0.0))
	var len_sec := float(ev.get("len_sec", 0.0))
	var loop := bool(ev.get("loop", false))
	var cache_key := file if (start_sec <= 0.0 and len_sec <= 0.0 and not loop) \
		else "%s#%s#%s#%s" % [file, start_sec, len_sec, loop]
	if _stream_cache.has(cache_key) and is_instance_valid(_stream_cache[cache_key]):
		return _stream_cache[cache_key]
	var stream: AudioStream = load(file) as AudioStream
	if stream == null:
		push_warning("Sfx: файл не найден: %s (событие %s)" % [file, event_name])
		return null
	if (start_sec > 0.0 or len_sec > 0.0 or loop) and stream is AudioStreamWAV:
		stream = _slice_wav(stream as AudioStreamWAV, start_sec, len_sec, file, loop)
		if stream == null:
			push_warning("Sfx: не удалось нарезать %s (событие %s)" % [file, event_name])
			return null
	_stream_cache[cache_key] = stream
	return stream

## Проиграть wav/ogg из файла с volume/pitch/delay (кэш загрузки).
## Возвращает true, если файл найден и запущен; false — нет файла/ошибка.
func _play_file(event_name: String, file: String, vol_db: float, pitch: float, delay: float) -> bool:
	var ev: Dictionary = _sound_cfg.get(event_name, {})
	var start_sec := float(ev.get("start_sec", 0.0))
	var len_sec := float(ev.get("len_sec", 0.0))
	var cache_key := file if (start_sec <= 0.0 and len_sec <= 0.0) else "%s#%s#%s" % [file, start_sec, len_sec]
	var stream: AudioStream = null
	if _stream_cache.has(cache_key) and is_instance_valid(_stream_cache[cache_key]):
		stream = _stream_cache[cache_key]
	else:
		stream = load(file) as AudioStream
		if stream == null:
			push_warning("Sfx: файл не найден: %s (событие %s)" % [file, event_name])
			return false
		# Нарезка wav под длину события (start_sec — пропустить интро,
		# len_sec — длина куска). Режем TOЛЬКО AudioStreamWAV.
		if (start_sec > 0.0 or len_sec > 0.0) and stream is AudioStreamWAV:
			stream = _slice_wav(stream as AudioStreamWAV, start_sec, len_sec, file)
			if stream == null:
				push_warning("Sfx: не удалось нарезать %s (событие %s)" % [file, event_name])
				return false
		_stream_cache[cache_key] = stream
	var p := _players[_rr]
	_rr = (_rr + 1) % _players.size()
	p.volume_db = vol_db + linear_to_db(maxf(sfx_volume, 0.001))
	p.pitch_scale = pitch
	p.stream = stream
	if delay > 0.0:
		# Отложенный старт без await: функция остаётся синхронной (bool).
		var timer := get_tree().create_timer(delay)
		timer.timeout.connect(func() -> void:
			if is_instance_valid(p):
				p.play())
	else:
		p.play()
	return true


## Нарезать PCM-файл (путь, WAV 16-bit/8-bit) на кусок [start_sec .. start_sec+len_sec]
## с коротким фейдом на конце. Читаем файл САМИ (минуя Godot-импорт, который
## перекодирует wav в ADPCM — тогда формат неизвестен). Null при ошибке.
func _slice_wav(w: AudioStreamWAV, start_sec: float, len_sec: float, file_path: String, loop: bool = false) -> AudioStreamWAV:
	if not FileAccess.file_exists(file_path):
		return null
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		return null
	var bytes := f.get_buffer(f.get_length())
	f.close()
	# Парсим WAV: ищем fmt (mix_rate, stereo) и data (смещение).
	var off := 12
	var sr := 44100
	var ch := 1
	var data_off := -1
	var data_size := 0
	while off + 8 <= bytes.size():
		var ck := bytes.slice(off, off + 4).get_string_from_ascii()
		var sz := bytes.decode_u32(off + 4)
		if ck == "fmt ":
			ch = bytes.decode_u16(off + 10)
			sr = bytes.decode_u32(off + 12)
		elif ck == "data":
			data_off = off + 8
			data_size = sz
			off += 8 + sz + (sz & 1)
			continue
		off += 8 + sz + (sz & 1)
	if data_off < 0 or sr <= 0:
		return null
	var bps := 2  # 16-bit PCM
	var frame_bytes := bps * ch
	if data_size <= 0 or frame_bytes <= 0:
		return null
	var total_frames := data_size / frame_bytes
	var start_f := int(start_sec * sr)
	var len_f := int(len_sec * sr) if len_sec > 0.0 else total_frames - start_f
	start_f = clampi(start_f, 0, total_frames - 1)
	len_f = clampi(len_f, 1, total_frames - start_f)
	var sub := bytes.slice(data_off + start_f * frame_bytes,
		data_off + (start_f + len_f) * frame_bytes)
	# Фейд-аут 10мс.
	var fade_frames := mini(int(0.010 * sr), len_f)
	for i in fade_frames:
		var idx := (len_f - fade_frames + i) * frame_bytes
		var v := int(sub.decode_s16(idx)) * (fade_frames - i) / fade_frames
		sub.encode_s16(idx, v)
		if ch == 2:
			var v2 := int(sub.decode_s16(idx + 2)) * (fade_frames - i) / fade_frames
			sub.encode_s16(idx + 2, v2)
	var out := AudioStreamWAV.new()
	out.format = AudioStreamWAV.FORMAT_16_BITS
	out.mix_rate = sr
	out.stereo = ch == 2
	out.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	out.loop_begin = 0
	out.loop_end = sub.size() / frame_bytes
	out.data = sub
	return out

func _play(samples: PackedFloat32Array, vol_db: float = 0.0) -> void:
	var p := _players[_rr]
	_rr = (_rr + 1) % _players.size()
	p.volume_db = vol_db + linear_to_db(maxf(sfx_volume, 0.001))
	p.stream = _make_wav(samples)
	p.play()

func _play_ui(samples: PackedFloat32Array, vol_db: float = 0.0) -> void:
	_play(samples, vol_db + UI_DB)

## Если в конфиге для события задан файл — проиграть его и вернуть true,
## иначе false (продолжить процедурный звук).
func _check_cfg_event(event_name: String) -> bool:
	var ev: Dictionary = _sound_cfg.get(event_name, {})
	var file := str(ev.get("file", ""))
	if file == "":
		return false
	return _play_file(event_name, file, float(ev.get("volume_db", 0.0)),
		float(ev.get("pitch", 1.0)), float(ev.get("delay", 0.0)))


func bubble() -> void:
	if _check_cfg_event("bubble"):
		return
	_play_ui(_sweep(randf_range(300.0, 640.0), randf_range(160.0, 320.0), 0.08, 0.5))

func click() -> void:
	if _check_cfg_event("click"):
		return
	_play_ui(_tone(1250.0, 0.035, 0.18, false))

func divide() -> void:
	if _check_cfg_event("divide"):
		return
	var a := _sweep(220.0, 520.0, 0.22, 0.5)
	var b := _tone(660.0, 0.25, 0.35)
	_play(_mix([a, b]))

func morph() -> void:
	if _check_cfg_event("morph"):
		return
	_play(_sweep(300.0, 900.0, 0.5, 0.3))

func draft_open() -> void:
	if _check_cfg_event("draft_open"):
		return
	_play_ui(_mix([_tone(440.0, 0.16, 0.22), _tone(660.0, 0.2, 0.18)]))

func legendary() -> void:
	if _check_cfg_event("legendary"):
		return
	var parts: Array = []
	for f in [523.0, 659.0, 784.0, 1046.0]:
		parts.append(_tone(f, 0.28, 0.2))
	_play(_mix(parts), -2.0)

func discovery() -> void:
	if _check_cfg_event("discovery"):
		return
	var a := _bell(784.0, 0.8, 0.12)
	var b := _bell(1174.7, 1.0, 0.09)
	_play(_mix([a, b]), -3.0)

func mystic() -> void:
	if _check_cfg_event("mystic"):
		return
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
	if _check_cfg_event("stage_up"):
		return
	var parts: Array = []
	for f in [392.0, 523.0, 659.0]:
		parts.append(_tone(f, 0.24, 0.22))
	_play(_mix(parts), -2.0)

func pet() -> void:
	if _check_cfg_event("pet"):
		return
	_play_ui(_sweep(700.0, 1400.0, 0.12, 0.3))

func error() -> void:
	if _check_cfg_event("error"):
		return
	_play_ui(_tone(170.0, 0.14, 0.3, false))

func _build_music() -> AudioStreamWAV:
	var secs := 24.0
	var n := int(secs * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var chords := [
		[110.0, 130.81, 164.81, 220.0],
		[87.31, 130.81, 174.61, 261.63],
		[130.81, 164.81, 196.0, 261.63],
		[98.0, 146.83, 196.0, 246.94]
	]
	var chord_len := int(secs / 4.0 * SR)
	for ci in 4:
		var freqs: Array = chords[ci]
		for i in chord_len:
			var t := float(i) / SR
			var seg := float(i) / float(chord_len)
			var env := pow(sin(PI * seg), 1.2)
			var v := 0.0
			for f in freqs:
				v += sin(TAU * f * t) * 0.45
				v += sin(TAU * (f * 1.008) * t) * 0.18
				v += sin(TAU * (f * 0.992) * t) * 0.18
				v += sin(TAU * f * 2.0 * t) * 0.1
			out[ci * chord_len + i] = v * env * 0.12
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
	_music_player.volume_db = 1.0 + linear_to_db(maxf(music_volume, 0.001))
