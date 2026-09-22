extends Control
# Главная сцена: собирает HUD, оверлеи, подписывается на события.
# Поток: тап по пузырькам -> энергия -> ДЕЛЕНИЕ -> выбор гена -> морф существа.
# Режим "--selftest": headless-проверки (CI/локально), выход с кодом 0/1.

const C_ACCENT := Color8(80, 224, 180)
const C_MUTED := Color8(150, 190, 180)
const C_TEXT := Color8(235, 255, 248)
const C_WARN := Color8(255, 176, 90)

var _dish: Node2D
var _bg: Control
var _draft: Control
var _genome: Control
var _energy_label: Label
var _cost_label: Label
var _stage_label: Label
var _dna_btn: Button
var _sound_btn: Button
var _hint_label: Label
var _toast_label: Label
var _div_btn: Button
var _energy_tween: Tween
var _pulse_t := 0.0
var _toast_t := -1.0
var _passive_acc := 0.0
var _selftest := false
var _st_total := 0
var _st_fails := 0
var _shot_path := ""
var _shot_genes := ""
var _shot_frame := 0

func _ready() -> void:
	_selftest = OS.get_cmdline_user_args().has("--selftest")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.substr("--shot=".length())
		elif a.begins_with("--genes="):
			_shot_genes = a.substr("--genes=".length())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_connect_events()
	_apply_state()

	# оффлайн-споры
	if GameState.pending_offline_gain > 1.0:
		toast(I18n.tf("offline_gain", [fmt(GameState.pending_offline_gain)]))
		GameState.pending_offline_gain = 0.0

	if not _selftest:
		var t := Timer.new()
		t.wait_time = 15.0
		t.autostart = true
		t.timeout.connect(GameState.save_game)
		add_child(t)

	if _selftest:
		_run_selftest()

func _build_ui() -> void:
	var font: Font = load("res://assets/fonts/NotoSans-Regular.ttf")
	if font != null:
		var th := Theme.new()
		th.default_font = font
		th.default_font_size = 20
		theme = th

	# --- фон: каустики/стекло/боке (под чашкой Петри) ---
	_bg = preload("res://game/dish_bg.gd").new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	# --- чашка Петри (существо и пузырьки) ---
	_dish = preload("res://game/dish.gd").new()
	add_child(_dish)

	# --- верхняя панель ---
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 96.0
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.02, 0.05, 0.06, 0.82)
	tsb.set_corner_radius_all(0)
	tsb.border_color = Color8(64, 190, 165, 60)
	tsb.set_border_width_all(1)
	top.add_theme_stylebox_override("panel", tsb)
	add_child(top)

	var top_m := MarginContainer.new()
	top_m.add_theme_constant_override("margin_left", 18)
	top_m.add_theme_constant_override("margin_right", 14)
	top_m.add_theme_constant_override("margin_top", 8)
	top_m.add_theme_constant_override("margin_bottom", 8)
	top.add_child(top_m)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	top_m.add_child(top_row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 2)
	top_row.add_child(left)

	_stage_label = _label("", 27, C_TEXT)
	left.add_child(_stage_label)

	var sub_row := HBoxContainer.new()
	sub_row.add_theme_constant_override("separation", 10)
	left.add_child(sub_row)

	_dna_btn = _button("", Vector2(0, 30))
	_dna_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dna_btn.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(GameState.dna_code())
		toast(I18n.t("copied")))
	sub_row.add_child(_dna_btn)

	var gen_btn := _button(I18n.t("genome_btn"), Vector2(0, 30))
	gen_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gen_btn.pressed.connect(func() -> void:
		Sfx.click()
		_genome.open())
	sub_row.add_child(gen_btn)

	_sound_btn = _button("", Vector2(0, 30))
	_sound_btn.pressed.connect(func() -> void:
		var on := Sfx.toggle_music()
		_sound_btn.text = I18n.t("sound_btn_on") if on else I18n.t("sound_btn_off"))
	top_row.add_child(_sound_btn)

	# --- тост ---
	_toast_label = _label("", 18, Color8(255, 235, 180))
	_toast_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toast_label.offset_top = 104.0
	_toast_label.offset_bottom = 140.0
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_toast_label.add_theme_constant_override("outline_size", 8)
	_toast_label.modulate.a = 0.0
	add_child(_toast_label)

	# --- нижняя панель ---
	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -216.0
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.02, 0.05, 0.06, 0.85)
	bsb.set_corner_radius_all(0)
	bsb.border_color = Color8(64, 190, 165, 60)
	bsb.set_border_width_all(1)
	bottom.add_theme_stylebox_override("panel", bsb)
	add_child(bottom)

	var bm := MarginContainer.new()
	bm.add_theme_constant_override("margin_left", 16)
	bm.add_theme_constant_override("margin_right", 16)
	bm.add_theme_constant_override("margin_top", 8)
	bm.add_theme_constant_override("margin_bottom", 10)
	bottom.add_child(bm)

	var bcol := VBoxContainer.new()
	bcol.add_theme_constant_override("separation", 4)
	bm.add_child(bcol)

	_energy_label = _label("", 30, C_ACCENT)
	_energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bcol.add_child(_energy_label)

	_cost_label = _label("", 16, C_MUTED)
	_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bcol.add_child(_cost_label)

	var btn_row := CenterContainer.new()
	bcol.add_child(btn_row)

	var div_btn := _button("", Vector2(132, 132))
	div_btn.text = I18n.t("divide")
	div_btn.add_theme_font_size_override("font_size", 22)
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color8(18, 70, 62)
	dsb.border_color = C_ACCENT
	dsb.set_border_width_all(4)
	dsb.set_corner_radius_all(70)
	var dsb_h: StyleBoxFlat = dsb.duplicate()
	dsb_h.bg_color = Color8(24, 96, 84)
	dsb_h.border_color = C_ACCENT.lightened(0.3)
	div_btn.add_theme_stylebox_override("normal", dsb)
	div_btn.add_theme_stylebox_override("hover", dsb_h)
	div_btn.add_theme_stylebox_override("pressed", dsb_h)
	div_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	div_btn.pressed.connect(_on_divide_pressed)
	div_btn.pivot_offset = Vector2(66, 66)
	_div_btn = div_btn
	btn_row.add_child(div_btn)

	# --- подсказка над нижней панелью ---
	_hint_label = _label(I18n.t("tap_hint"), 16, C_MUTED)
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.offset_top = -260.0
	_hint_label.offset_bottom = -232.0
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)

	# --- оверлеи ---
	_draft = preload("res://scenes/draft_overlay.gd").new()
	add_child(_draft)
	_draft.picked.connect(_on_gene_picked)
	_genome = preload("res://scenes/genome_overlay.gd").new()
	add_child(_genome)

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _button(text: String, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	if min_size.x > 0:
		b.custom_minimum_size = min_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(26, 48, 52)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	var sb_h: StyleBoxFlat = sb.duplicate()
	sb_h.bg_color = Color8(38, 66, 70)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb_h)
	b.add_theme_stylebox_override("pressed", sb_h)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color8(215, 240, 233))
	return b

func _connect_events() -> void:
	EventBus.energy_changed.connect(func(_v: float) -> void: _update_energy())
	EventBus.genome_changed.connect(func(_ids: Array) -> void: _on_genome_changed())
	EventBus.stage_changed.connect(func(_o: int, _n: int) -> void: _on_stage_changed(_o, _n))

func _apply_state() -> void:
	_update_energy()
	_update_stage_label()
	_update_dna_label()
	_sound_btn.text = I18n.t("sound_btn_on") if Sfx.music_on else I18n.t("sound_btn_off")
	if not GameState.genome_ids.is_empty():
		_hint_label.visible = false
	if _shot_genes != "":
		# dev-режим скриншотов: подменить геном
		var ids: Array = []
		for id in _shot_genes.split(","):
			ids.append(id)
		GameState.genome_ids.assign(ids)
		GameState.energy = 500.0
		GameState.divisions = ids.size()
		_update_energy()
		_update_stage_label()
		_update_dna_label()
		_dish.apply_genome(GameState.genome_ids)
	else:
		_dish.apply_genome(GameState.genome_ids)
	_bg.call("set_stage", GameState.stage_index(), true)

func _update_energy() -> void:
	_energy_label.text = "⚡  " + fmt(GameState.energy)
	var need := fmt(GameState.divide_cost())
	_cost_label.text = I18n.tf("divide_cost", [need])
	_cost_label.add_theme_color_override("font_color", C_ACCENT if GameState.can_divide() else C_WARN)
	# «попап» счётчика при изменении
	if _energy_tween != null and _energy_tween.is_valid():
		_energy_tween.kill()
	_energy_label.pivot_offset = _energy_label.size * 0.5
	_energy_label.scale = Vector2.ONE
	_energy_tween = create_tween()
	_energy_tween.tween_property(_energy_label, "scale", Vector2(1.14, 1.14), 0.09) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_energy_tween.tween_property(_energy_label, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _update_stage_label() -> void:
	var st := clampi(GameState.stage_index(), 0, 7)
	_stage_label.text = I18n.t("stage") + ": " + I18n.t("s" + str(st))

func _update_dna_label() -> void:
	_dna_btn.text = I18n.tf("dna", [GameState.dna_code()])

func _on_divide_pressed() -> void:
	if not GameState.do_divide():
		Sfx.error()
		toast(I18n.t("not_enough"))
		return
	Sfx.divide()
	Input.vibrate_handheld(25)
	_update_energy()
	# маленькая пауза перед драблом
	get_tree().create_timer(0.6).timeout.connect(_open_draft)

func _open_draft() -> void:
	if _selftest:
		return
	_draft.open()

func _on_gene_picked(id: String) -> void:
	GameState.add_gene(id)
	Sfx.morph()
	var g: Dictionary = GameState.gene_by_id(id)
	if not g.is_empty() and int(g.get("rarity", 0)) >= 3:
		Sfx.legendary()
		toast(I18n.t("legendary_found"))

func _on_genome_changed() -> void:
	_dish.apply_genome(GameState.genome_ids)
	_update_dna_label()
	if not GameState.genome_ids.is_empty():
		_hint_label.visible = false

func _on_stage_changed(_old: int, new_idx: int) -> void:
	_update_stage_label()
	_bg.call("set_stage", new_idx, false)
	if _selftest:
		return
	Sfx.stage_up()
	toast(I18n.tf("new_stage", [I18n.t("s" + str(clampi(new_idx, 0, 7)))]))

func toast(text: String) -> void:
	_toast_label.text = text
	_toast_label.modulate.a = 1.0
	_toast_t = 2.6

func fmt(v: float) -> String:
	var x := v
	if x >= 1.0e12:
		return "%.2fT" % [x / 1.0e12]
	if x >= 1.0e9:
		return "%.2fB" % [x / 1.0e9]
	if x >= 1.0e6:
		return "%.2fM" % [x / 1.0e6]
	if x >= 1.0e3:
		return "%.1fK" % [x / 1.0e3]
	return str(int(x))

func _process(delta: float) -> void:
	if _shot_path != "":
		_shot_frame += 1
		if _shot_frame >= 40:
			var img := get_viewport().get_texture().get_image()
			var err := img.save_png(_shot_path)
			print("SHOT ", _shot_path, " err=", err)
			get_tree().quit(0)
		return
	_pulse_t += delta
	# пульсация кнопки «Деление», когда хватает энергии
	if _div_btn != null:
		var afford := GameState.can_divide()
		_div_btn.modulate = Color(1, 1, 1, 1) if afford else Color(0.62, 0.75, 0.78, 0.85)
		var k := 1.0
		if afford:
			k = 1.0 + 0.045 * (0.5 + 0.5 * sin(_pulse_t * 4.2))
		if absf(_div_btn.scale.x - k) > 0.0001:
			_div_btn.scale = Vector2(k, k)
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t < 0.9:
			_toast_label.modulate.a = clampf(_toast_t / 0.9, 0.0, 1.0)
	if _selftest:
		return
	# пассивная энергия (автотрофы) — аккуратно, без сигналов на каждый кадр
	var passive := GameState.passive_energy_per_sec()
	if passive > 0.0:
		_passive_acc += passive * delta
		if _passive_acc >= 0.25:
			GameState.add_energy(_passive_acc)
			_passive_acc = 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		GameState.save_game()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _genome != null and _genome.visible:
			_genome.visible = false
		elif _draft != null and _draft.visible:
			_draft.visible = false
		else:
			GameState.save_game()
			get_tree().quit()

# ================= headless-селфтесты =================

func _check(name: String, cond: bool) -> void:
	_st_total += 1
	if cond:
		print("[OK] ", name)
	else:
		_st_fails += 1
		print("[FAIL] ", name)
		push_error("SELFTEST FAIL: " + name)

func _run_selftest() -> void:
	_st_total = 0
	_st_fails = 0

	# 1. i18n
	_check("i18n keys", I18n.t("s0") != "s0" and I18n.t("divide") != "divide")
	# 2. данные генов
	var genes: Array = GameState.gene_list()
	_check("genes >= 10", genes.size() >= 10)
	var first: Dictionary = genes[0]
	_check("gene has both langs",
		not first["name"]["ru"].is_empty() and not first["name"]["en"].is_empty())
	# 3. дефолтный фенотип
	_check("default pheno", PhenotypeEngine.default_pheno()["size"] == 1.0)
	# 4. детерминизм
	var a := ["fast_mitosis", "gigantism", "eyes"]
	_check("deterministic",
		JSON.stringify(PhenotypeEngine.compute(a)) == JSON.stringify(PhenotypeEngine.compute(a)))
	# 5. порядок генов влияет (эпистаз gigantism|chitin_armor)
	var fwd: Dictionary = PhenotypeEngine.compute(["gigantism", "chitin_armor"])
	var rev: Dictionary = PhenotypeEngine.compute(["chitin_armor", "gigantism"])
	_check("order matters (epistasis)", int(fwd["spikes"]) == 10 and int(rev["spikes"]) == 6)
	# 6. стадии
	_check("stage thresholds", PhenotypeEngine.stage_of(0) == 0 and PhenotypeEngine.stage_of(3) == 1
		and PhenotypeEngine.stage_of(30) == 7)
	# 7. экономика
	var c0 := GameState.divide_cost()
	GameState.divisions = 3
	var c3 := GameState.divide_cost()
	GameState.divisions = 0
	_check("divide cost grows", c3 > c0 and c0 > 20.0 and c0 < 200.0)
	# 8. код ДНК
	var prev_ids: Array = GameState.genome_ids
	GameState.genome_ids = ["fast_mitosis", "eyes"]
	var dna1 := GameState.dna_code()
	GameState.genome_ids = ["eyes", "fast_mitosis"]
	var dna2 := GameState.dna_code()
	GameState.genome_ids = prev_ids
	_check("dna distinct", dna1 != dna2 and dna1.begins_with("QB-"))
	# 9. драбл: только доступные, 3 разных (без повторов)
	GameState.genome_ids = []
	var cands: Array = GameState.make_candidates(3)
	_check("draft 3 distinct unlocked", cands.size() == 3
		and cands[0]["id"] != cands[1]["id"] and cands[1]["id"] != cands[2]["id"])
	# 9.1 доступность легендарного гена — по требованиям (детерминированно,
	# без выборки: старая проверка была стохастической и «плавала» от сида RNG)
	var has_quantum := false
	for g in GameState.unlocked_genes():
		if g["id"] == "quantum_aura":
			has_quantum = true
	_check("quantum locked without biolum", not has_quantum)
	GameState.genome_ids = ["bioluminescence"]
	has_quantum = false
	for g in GameState.unlocked_genes():
		if g["id"] == "quantum_aura":
			has_quantum = true
	_check("quantum unlocked with biolum", has_quantum)
	# 10.5 UI-оверлеи открываются без ошибок
	GameState.genome_ids = []
	_draft.call("open")
	var draft_visible: bool = _draft.visible
	var card_box: Variant = _draft.get("_cards_box")
	var cards := -1
	if card_box != null:
		cards = (card_box as HBoxContainer).get_child_count()
	_draft.visible = false
	_check("draft overlay opens 3 cards", draft_visible and cards == 3)
	GameState.genome_ids = ["fast_mitosis", "eyes", "segmentation"]
	_genome.call("open")
	var row_box: Variant = _genome.get("_rows_box")
	var rows := -1
	if row_box != null:
		rows = (row_box as VBoxContainer).get_child_count()
	_genome.visible = false
	_check("genome overlay lists genes", rows == 3)
	# 10.6 полный цикл деления через API
	var prev_div: int = GameState.divisions
	GameState.energy = GameState.divide_cost() + 5.0
	var did: bool = GameState.do_divide()
	_check("do_divide full cycle", did and GameState.divisions == prev_div + 1
		and absf(GameState.energy - 5.0) < 0.01)
	# 10.7 перемешивание генома (раньше падало: у RNG нет shuffle())
	GameState.genome_ids = ["fast_mitosis", "eyes", "flagella", "segmentation"]
	var sorted_before := GameState.genome_ids.duplicate()
	sorted_before.sort()
	GameState.shuffle_genome()
	var sorted_after := GameState.genome_ids.duplicate()
	sorted_after.sort()
	_check("shuffle keeps genome set", sorted_before == sorted_after
		and GameState.genome_ids.size() == 4)
	# 10.8 тап по пузырьку (логика игрового поля, мышь/тач)
	var drops_arr: Array = _dish.get("drops")
	drops_arr.clear()
	_dish.call("spawn_drop", Vector2(360, 900))
	GameState.energy = 0.0
	_dish.call("_handle_tap", Vector2(360, 900))
	_check("bubble tap adds energy", GameState.energy > 0.0)
	GameState.energy = 0.0
	_dish.call("_handle_tap", Vector2(40, 40))
	_check("empty tap adds nothing", GameState.energy == 0.0)
	# 10.9 полный геном: драбл не пуст (повторная экспрессия купленных генов)
	var full: Array = []
	for g in GameState.gene_list():
		full.append(g["id"])
	GameState.genome_ids.assign(full)
	var cands_full: Array = GameState.make_candidates(3)
	_check("draft works when genome full", cands_full.size() == 3
		and cands_full[0]["id"] != cands_full[1]["id"]
		and cands_full[1]["id"] != cands_full[2]["id"])
	# 10. сейв roundtrip
	GameState.save_path = "user://qb_selftest_save_v1.json"
	if FileAccess.file_exists(GameState.save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	GameState.energy = 123.5
	GameState.divisions = 4
	GameState.genome_ids = ["fast_mitosis", "segmentation", "eyes"]
	GameState.save_game()
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(GameState.save_path))
	var d: Dictionary = raw
	_check("save roundtrip",
		d.get("energy") == 123.5 and d.get("divisions") == 4
		and (d.get("genome") as Array).size() == 3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	GameState.save_path = "user://qb_save_v1.json"

	print("SELFTEST ", "PASS" if _st_fails == 0 else "FAIL",
		" (", _st_total - _st_fails, "/", _st_total, ")")
	get_tree().quit(0 if _st_fails == 0 else 1)
