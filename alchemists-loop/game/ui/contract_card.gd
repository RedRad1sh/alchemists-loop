extends Control
class_name ContractCard

# §5.3: бумажка контракта на доске. Виджет только показывает состояние, которое посчитали
# в Contracts, и просит у доски выдачу — сам ничего не выдаёт (решение 4).

const ASSET_DIR := "res://assets/contracts/"
const FADE_SHADER := "res://assets/contracts/paper_fade.gdshader"
const DAILY_SIZE := Vector2(140, 196)
const WEEKLY_SIZE := Vector2(184, 244)
const TILT_MAX := 4.0
const NAIL_SIZE := 32.0
const SEAL_SIZE := 52.0
const STAMP_SIZE := Vector2(132, 56)
const STAMP_TILT := -6.0
const PAD := 14.0
const HOVER_SCALE := 1.03
const HOVER_SECONDS := 0.12
const SEAL_SCALE := 1.5
const SEAL_ROT := -8.0
const SEAL_SECONDS := 0.18
# Полоса тела карточки (доска v2, Task 7): между счётчиком и наградой.
const DETAIL_TOP := 70.0
const DETAIL_GAP := 4.0
# Насколько можно увести курсор между нажатием и отпусканием, чтобы клик
# всё ещё считался тапом по бумаге, а не началом перетаскивания доски.
const TAP_SLOP := 10.0

const INK := Color(0.16, 0.11, 0.07)
const STAMP_INK := Color(0.60, 0.24, 0.20)
const TIER_INK := {
	"bronze": Color(0.55, 0.33, 0.14),
	"silver": Color(0.42, 0.47, 0.53),
	"gold": Color(0.62, 0.45, 0.08),
}

signal claimed(id: String)

var g: Game
var _c: Dictionary = {}
var _hang: Control
var _fade: ShaderMaterial
var _paper: TextureRect
var _title: Label
var _count: Label
var _detail: VBoxContainer
var _reward: Label
var _seal: TextureRect
var _stamp: TextureButton
var _stamp_word: Label
var _nail: TextureRect
var _hover_on := false
var _pressed := false
var _press_pos := Vector2.ZERO
var _last_y := 0.0

static func tex(fname: String) -> Texture2D:
	return load(ASSET_DIR + fname) as Texture2D

# Наклон по id, детерминированный между сборками: FNV-1a тот же, что у `_seed_for`
# в доске, а `String.hash()` движок солёт иначе — и бумаги прыгали бы при каждом
# перезапуске (решение 3).
static func rot_deg(id: String) -> float:
	var h := 2166136261
	for byte in id.to_utf8_buffer():
		h = ((h ^ int(byte)) * 16777619) & 0x7FFFFFFF
	return TILT_MAX * (2.0 * float(h % 1001) / 1000.0 - 1.0)

func _init(game: Game) -> void:
	g = game
	name = "ContractCard"
	mouse_filter = Control.MOUSE_FILTER_STOP

func setup(c: Dictionary) -> void:
	_c = c
	var weekly := String(c.get("kind", "daily")) == "weekly"
	var sz := WEEKLY_SIZE if weekly else DAILY_SIZE
	var w := sz.x
	var h := sz.y
	if _hang == null:
		_build()
	custom_minimum_size = sz
	_hang.size = sz
	# Пивот — точка, в которую вбит гвоздь: лист качается вокруг него, а не вокруг центра.
	_hang.pivot_offset = Vector2(w / 2.0, 0.0)
	_hang.rotation_degrees = rot_deg(String(c["id"]))
	scale = Vector2.ONE
	_paper.size = sz
	_paper.texture = tex("paper_weekly.png") if weekly else tex("paper_daily.png")
	_title.position = Vector2(PAD, 16.0)
	_title.size = Vector2(w - 2.0 * PAD, 22.0)
	_title.add_theme_color_override("font_color",
		TIER_INK.get(String(c.get("tier", "bronze")), INK))
	_count.position = Vector2(PAD, 44.0)
	_count.size = Vector2(w - 2.0 * PAD, 26.0)
	# Тело карточки — между счётчиком и наградой; размеры существующих полей не
	# тронуты (бриф Task 7), полоса тела берёт оставшееся paper-окно.
	_detail.position = Vector2(PAD, DETAIL_TOP)
	_detail.size = Vector2(w - 2.0 * PAD, h - DETAIL_TOP - 78.0 - DETAIL_GAP)
	_reward.position = Vector2(PAD, h - 78.0)
	_reward.size = Vector2(w - 2.0 * PAD, 62.0)
	_seal.position = Vector2(w - SEAL_SIZE + 4.0, h - SEAL_SIZE + 4.0)
	_seal.size = Vector2(SEAL_SIZE, SEAL_SIZE)
	_seal.texture = tex("seal_%s.png" % String(c.get("tier", "bronze")))
	_stamp.position = Vector2((w - STAMP_SIZE.x) / 2.0, h - 112.0)
	# Гвоздь — ребёнок карточки, не листа: он в доске и не поворачивается.
	_nail.position = Vector2(w / 2.0 - NAIL_SIZE / 2.0, -NAIL_SIZE / 2.0)
	_nail.size = Vector2(NAIL_SIZE, NAIL_SIZE)

	var id := String(c["id"])
	var done := g._contracts.is_done(id)
	_title.text = String(ContractsBalance.TITLE.get(String(c.get("type", "")), ""))
	_count.text = "%d / %d" % [g._contracts.progress(id), int(c.get("goal", 0))]
	_reward.text = _reward_text(c)
	var tip := _reward_tip(c)
	_reward.tooltip_text = tip
	_stamp.tooltip_text = tip
	_stamp.visible = done or g._contracts.is_ready(id)
	_stamp.disabled = done
	# Материал OWN: у каждой карточки свой экземпляр, иначе одна полученная записка
	# обесцветила бы всю доску.
	_fade.set_shader_parameter("amount", 1.0 if done else 0.0)
	_fill_detail(id, String(c.get("type", "")))

func _build() -> void:
	_hang = Control.new()
	_hang.name = "Hang"
	_hang.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hang)
	_fade = ShaderMaterial.new()
	_fade.shader = load(FADE_SHADER) as Shader
	_hang.material = _fade

	_paper = TextureRect.new()
	_paper.name = "Paper"
	_paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_paper.stretch_mode = TextureRect.STRETCH_SCALE
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hang.add_child(_paper)

	_title = g._label("", 14)
	_title.name = "Title"
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if g._font_semi != null:
		_title.add_theme_font_override("font", g._font_semi)
	_title.add_theme_color_override("font_color", INK)
	_hang.add_child(_title)

	_count = g._label("", 18)
	_count.name = "Count"
	_count.autowrap_mode = TextServer.AUTOWRAP_OFF
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.add_theme_color_override("font_color", INK)
	_hang.add_child(_count)

	# Тело карточки (доска v2, Task 7, спека §5): goal_day — строка цели,
	# vein — ряды капель, fair — строка котла. Обычный VBox: карточка сама
	# задаёт ему position/size (контейнер в ряду доски не сидит).
	_detail = VBoxContainer.new()
	_detail.name = "Detail"
	_detail.add_theme_constant_override("separation", 2)
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hang.add_child(_detail)

	_reward = g._label("", 11)
	_reward.name = "Reward"
	_reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reward.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_reward.clip_text = true
	# Строка награды ловит мышь: наведение показывает точную награду (§5.3),
	# потому что «Быстрая варка» без процента и срока для игрока — загадка.
	# PASS, а не STOP: тултип остаётся, а hover и тап уходят бумаге.
	_reward.mouse_filter = Control.MOUSE_FILTER_PASS
	_reward.add_theme_color_override("font_color", INK)
	_hang.add_child(_reward)

	_seal = TextureRect.new()
	_seal.name = "Seal"
	_seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hang.add_child(_seal)

	_stamp = TextureButton.new()
	_stamp.name = "Stamp"
	_stamp.size = STAMP_SIZE
	_stamp.ignore_texture_size = true
	_stamp.stretch_mode = TextureButton.STRETCH_SCALE
	_stamp.focus_mode = Control.FOCUS_NONE
	var stamp_tex := tex("stamp_frame.png")
	_stamp.texture_normal = stamp_tex
	_stamp.texture_pressed = stamp_tex
	_stamp.texture_hover = stamp_tex
	_stamp.texture_disabled = stamp_tex
	_stamp.pivot_offset = STAMP_SIZE / 2.0
	_stamp.rotation_degrees = STAMP_TILT
	_stamp.pressed.connect(_on_stamp_pressed)
	_hang.add_child(_stamp)

	# Текст штампа — ребёнок TextureButton: это Control, но не Container, поэтому у ребёнка
	# явные position/size (rule 27 плюс память проекта про «Button не контейнер»).
	_stamp_word = g._label("ИСПОЛНЕНО", 12)
	_stamp_word.name = "StampWord"
	_stamp_word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamp_word.autowrap_mode = TextServer.AUTOWRAP_OFF
	_stamp_word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stamp_word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stamp_word.add_theme_color_override("font_color", STAMP_INK)
	_stamp_word.size = STAMP_SIZE
	_stamp.add_child(_stamp_word)

	_nail = TextureRect.new()
	_nail.name = "Nail"
	_nail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_nail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_nail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nail.texture = tex("nail_brass.png")
	add_child(_nail)

func _on_stamp_pressed() -> void:
	Sfx.click()
	_seal_slam()
	claimed.emit(String(_c["id"]))


## Печать: штамп влетает с +50% размера и доворотом −8°, TRANS_BACK садится
## на прежний наклон; кольцо расходится по чернилам; бумага вздрагивает
## вокруг гвоздя. Под selftest — мгновенная поза покоя (ничего не висит).
func _seal_slam() -> void:
	if not Juice.enabled:
		_stamp.scale = Vector2.ONE
		_stamp.rotation_degrees = STAMP_TILT
		return
	_stamp.pivot_offset = STAMP_SIZE * 0.5
	Juice._kill_prev(_stamp)
	_stamp.scale = Vector2(SEAL_SCALE, SEAL_SCALE)
	_stamp.rotation_degrees = STAMP_TILT + SEAL_ROT
	var tw := _stamp.create_tween()
	tw.tween_property(_stamp, "scale", Vector2.ONE, SEAL_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_stamp, "rotation_degrees", STAMP_TILT, SEAL_SECONDS)
	_stamp.set_meta(Juice.META_TWEEN, tw)
	var r := _stamp.get_global_rect()
	Juice.ring(_stamp, r.get_center(), STAMP_INK, maxf(36.0, r.size.x * 0.45))
	var sh := _hang.create_tween()
	sh.tween_property(_hang, "scale", Vector2(0.985, 0.985), 0.05)
	sh.tween_property(_hang, "scale", Vector2(1.005, 1.005), 0.05)
	sh.tween_property(_hang, "scale", Vector2.ONE, 0.04)


## Наведение опрашиваем, а не слушаем mouse_entered/exited: сигналы корня
## молчат, когда курсор встал на STOP-ребёнка (штамп, кнопка «Влить»), и лист
## «гас» на половине своей площади. Опрос по hovered_control + подъём
## по предкам покрывает бумагу целиком.
func _process(_delta: float) -> void:
	var over := _covers(_hovered_control())
	if over == _hover_on:
		return
	_hover_on = over
	_set_hover(over)

func _hovered_control() -> Control:
	var vp := get_viewport()
	return vp.gui_get_hovered_control() if vp != null else null

func _covers(hc: Control) -> bool:
	while hc != null:
		if hc == self:
			return true
		hc = hc.get_parent_control()
	return false

## Тап по любому месту бумаги закрывает контракт — раньше попадание шло только
## по штампу, и игрок тыкал в бумагу без ответа. Увод курсора дальше TAP_SLOP
## считаем перетаскиванием доски и передаём его ей: бумага ловит ввод (STOP),
## поэтому сама доска эти события не увидела бы, а на Android колеса нет.
func _gui_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_pressed = true
			_press_pos = mb.global_position
			_last_y = mb.global_position.y
			return
		var was_press := _pressed
		_pressed = false
		if not was_press or _press_pos.distance_to(mb.global_position) > TAP_SLOP:
			return
		if _stamp == null or not _stamp.visible or _stamp.disabled:
			return
		accept_event()
		_on_stamp_pressed()
		return
	var mm := ev as InputEventMouseMotion
	if mm == null or not _pressed:
		return
	# Только global_position: лист сам уезжает под пальцем при прокрутке, и
	# локальная координата дала бы петлю — сдвиг ряда снова читался бы как
	# движение пальца и доска листала себя сама.
	if _press_pos.distance_to(mm.global_position) <= TAP_SLOP:
		return
	var board := g.get_node_or_null("ContractBoard")
	if board == null or not board.has_method("_scroll_by"):
		return
	accept_event()
	board._scroll_by(_last_y - mm.global_position.y)
	_last_y = mm.global_position.y


## Лист приподнимается к курсору. Под selftest и на тач-пути — без твина:
## scale выставляется сразу (или не трогается вовсе при выходе).
func _set_hover(on: bool) -> void:
	var to := Vector2.ONE
	if on:
		to = Vector2.ONE * HOVER_SCALE
	if not Juice.enabled:
		scale = to
		return
	pivot_offset = size * 0.5
	Juice._kill_prev(self)
	var tw := create_tween()
	tw.tween_property(self, "scale", to, HOVER_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	set_meta(Juice.META_TWEEN, tw)

# Строка награды: материалы (уже масштабированные в reward_for), бафф, витраж.
# Пустая строка поля = ничего не упоминаем, « · · » на доске быть не может.
func _reward_text(c: Dictionary) -> String:
	var r: Dictionary = g._contracts.reward_for(c)
	var mats: Dictionary = r["materials"]
	var names: Array = []
	for m in mats:
		names.append("%s ×%d" % [g._online._item_name(String(m)), int(mats[m])])
	var parts: Array = []
	if not names.is_empty():
		parts.append(", ".join(names))
	var buff := String(r["buff"])
	if buff != "":
		parts.append(String(ContractsBalance.BUFF_TITLE.get(buff, "")))
	var decor := String(r["decor"])
	if decor != "":
		parts.append(String(ContractsBalance.DECOR_LABEL.get(decor, "")))
	return " · ".join(parts)

# Точная награда для наведения: процент силы и срок баффа печатаются из
# reward_for — на бумаде их нет, единый множитель §3.1 меняет числа каждый день.
func _reward_tip(c: Dictionary) -> String:
	var r: Dictionary = g._contracts.reward_for(c)
	var lines: Array = []
	var mats: Dictionary = r["materials"]
	var names: Array = []
	for m in mats:
		names.append("%s ×%d" % [g._online._item_name(String(m)), int(mats[m])])
	if not names.is_empty():
		lines.append("Материалы: " + ", ".join(names))
	var buff := String(r["buff"])
	if buff != "":
		lines.append("%s — %s (+%d%%, %s)" % [String(ContractsBalance.BUFF_TITLE.get(buff, "")),
			String(ContractsBalance.BUFF_TEXT.get(buff, "")),
			int(round(100.0 * float(r["power"]))), ContractBoard._mm(int(r["duration"]))])
	var decor := String(r["decor"])
	if decor != "":
		lines.append("%s — украсит Дом" % String(ContractsBalance.DECOR_LABEL.get(decor, "")))
	return "\n".join(lines)

# ---------- доска v2 (Task 7, спека §5): тела карточек goal_day/vein/fair ----------
# Карточка ничего не считает: строки цели/котла приходят из Contracts
# (card_detail_lines), ряды капель — из vein_drop_rows. Пересобирается на
# каждом setup(): доска перевызывает setup() при каждом refresh().
func _fill_detail(id: String, type: String) -> void:
	for ch in _detail.get_children():
		_detail.remove_child(ch)
		ch.queue_free()
	if type == "vein":
		_fill_vein()
		return
	var lines: Array = g._contracts.card_detail_lines(id)
	for raw in lines:
		var l := g._label(String(raw), 10)
		l.name = "FairPot" if type == "fair" else "GoalDay"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", INK)
		# Строка тела ловит мышь: у goal_day в tooltip — подсказка мира.
		# PASS, а не STOP: тултип остаётся, hover и тап уходят бумаге.
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		if type == "goal_day":
			var hint := g._contracts.day_hint()
			if hint != "":
				l.tooltip_text = "мир: %s" % hint
		_detail.add_child(l)

# Жила: мини-капли VeinDrop текущего цикла; у registered — «Влить». Три ряда
# влезают в weekly-полосу (184×244), остальные сворачиваются в «…ещё N».
func _fill_vein() -> void:
	var rows: Array = g._contracts.vein_drop_rows()
	var shown := mini(rows.size(), 3)
	for i in range(shown):
		var row_data := rows[i] as Dictionary
		var st := String(row_data["status"])
		var hbox := HBoxContainer.new()
		hbox.name = "VeinDropRow%d" % i
		hbox.add_theme_constant_override("separation", 3)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_detail.add_child(hbox)
		var drop := VeinDrop.new()
		drop.setup(row_data["color"] as Color, st, Vector2(18, 22))
		hbox.add_child(drop)
		var word := "ждёт мира" if st == "pending_server" else ("влита ✓" \
			if st == "poured" or st == "auto_applied" else "«%s»" % String(row_data["tag"]))
		var fl := g._label(word, 9)
		fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		fl.autowrap_mode = TextServer.AUTOWRAP_OFF
		fl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		fl.add_theme_color_override("font_color", INK)
		hbox.add_child(fl)
		if st == "registered":
			var pb := Button.new()
			pb.name = "Pour"
			pb.text = "Влить"
			pb.custom_minimum_size = Vector2(44, 22)
			pb.focus_mode = Control.FOCUS_NONE
			pb.add_theme_font_size_override("font_size", 10)
			UIStyle.style_button(pb, 2, 6)
			pb.pressed.connect(_on_pour_pressed.bind(String(row_data["find_id"])))
			pb.pressed.connect(func() -> void: Juice.pop(drop, row_data["color"] as Color))
			hbox.add_child(pb)
	if rows.size() > shown:
		var more := g._label("…ещё %d" % (rows.size() - shown), 9)
		more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		more.add_theme_color_override("font_color", INK)
		_detail.add_child(more)

func _on_pour_pressed(find_id: String) -> void:
	Sfx.click()
	g._contracts._vein_pour(find_id)
