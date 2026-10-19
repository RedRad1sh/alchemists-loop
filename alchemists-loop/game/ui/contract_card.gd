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
var _reward: Label
var _seal: TextureRect
var _stamp: TextureButton
var _stamp_word: Label
var _nail: TextureRect

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
	mouse_filter = Control.MOUSE_FILTER_IGNORE

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
	_paper.size = sz
	_paper.texture = tex("paper_weekly.png") if weekly else tex("paper_daily.png")
	_title.position = Vector2(PAD, 16.0)
	_title.size = Vector2(w - 2.0 * PAD, 22.0)
	_title.add_theme_color_override("font_color",
		TIER_INK.get(String(c.get("tier", "bronze")), INK))
	_count.position = Vector2(PAD, 44.0)
	_count.size = Vector2(w - 2.0 * PAD, 26.0)
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

	_reward = g._label("", 11)
	_reward.name = "Reward"
	_reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reward.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_reward.clip_text = true
	# Строка награды ловит мышь: наведение показывает точную награду (§5.3),
	# потому что «Быстрая варка» без процента и срока для игрока — загадка.
	_reward.mouse_filter = Control.MOUSE_FILTER_STOP
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
	_stamp.scale = Vector2(0.90, 0.90)
	create_tween().tween_property(_stamp, "scale", Vector2.ONE, 0.13) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	claimed.emit(String(_c["id"]))

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
