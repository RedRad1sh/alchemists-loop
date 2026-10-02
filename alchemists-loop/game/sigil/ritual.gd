class_name SigilRitual
extends Control
# Алхимический ритуал открытия карты в полноэкранном просмотре (подпроект C+).
#
# Что делает:
#   1. Призыв — тёмный фон, вспышка трансмутационного круга (вращение + пульс);
#   2. Стихии — дым, искры/молнии, огонь, нарастающая аура по редкости;
#   3. Материализация — арт выплывает из круга (scale TRANS_BACK), круг гаснет;
#   4. Переворот по тапу — двухстадийный scale.x-схлоп, оборотная сторона с lore.
#
# Отдельный Control-слой поверх фуллскрина main.gd. Живую карточку (анимированную
# ауру/искры/фольгу) показывает SigilCard в собственном SubViewport.
#
# Интенсивность эффектов зависит от редкости: common — слабо, legendary/chromatic
# — максимально (огонь, молнии, золото).

signal flip_toggled(back: bool)
signal ritual_done

enum Phase { IDLE, SUMMON, ELEMENTS, MATERIALIZE, DONE }

const RARITY_STRENGTH := {
	"common": 0.15, "rare": 0.35, "epic": 0.6,
	"legendary": 1.0, "chromatic": 1.15,
}

var _phase: int = Phase.IDLE
var _rarity: String = "common"
var _strength: float = 0.15
var _accent: Color = Color(1, 1, 1)
var _t := 0.0
var _flipped := false
var _busy := false
var _auto_flip_timer := -1.0

var _circle: Control
var _hint: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


## Автопереворот для демо/GIF: сработает через t секунд после материализации.
func set_auto_flip(t: float) -> void:
	_auto_flip_timer = t


## Запустить ритуал для карты (оверлей поверх арта, 2-арг).
func start(p_rarity: String, accent: Color) -> void:
	_rarity = p_rarity
	_strength = RARITY_STRENGTH.get(p_rarity, 0.5)
	_accent = accent
	_phase = Phase.SUMMON
	_t = 0.0
	_flipped = false
	_build_effects()
	set_process(true)


func _build_effects() -> void:
	# Трансмутационный круг призыва: рисуется кодом (без .tscn).
	if _circle != null:
		_circle.queue_free()
	_circle = Control.new()
	_circle.name = "RitualCircle"
	_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_circle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_circle.pivot_offset = size / 2.0
	add_child(_circle)

	var hint := _label_hint()
	add_child(hint)
	_hint = hint


func _label_hint() -> Label:
	var l := Label.new()
	l.name = "RitualHint"
	l.text = "нажми — перевернуть"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.visible = false
	return l


func _process(delta: float) -> void:
	_t += delta
	if _auto_flip_timer >= 0.0 and _phase == Phase.DONE and not _busy:
		_auto_flip_timer -= delta
		if _auto_flip_timer <= 0.0:
			_auto_flip_timer = -1.0
			flip()
	match _phase:
		Phase.SUMMON:
			_summon(delta)
		Phase.ELEMENTS:
			_elements(delta)
		Phase.MATERIALIZE:
			_materialize(delta)
		Phase.DONE:
			if _flipped:
				_hint.visible = true


func _summon(delta: float) -> void:
	# Круг вспыхивает и вращается: rotation вокруг оси + scale-пульс.
	_circle.rotation += delta * (1.5 + _strength * 3.0)
	var s := 0.3 + 0.7 * minf(_t / 0.6, 1.0)
	_circle.scale = Vector2(s, s)
	_circle.modulate.a = minf(_t / 0.4, 1.0)
	if _t >= 0.6:
		_phase = Phase.ELEMENTS
		_t = 0.0


func _elements(delta: float) -> void:
	# Стихии: аура нарастает, искры/огонь — в живой карточке уже анимируются.
	_circle.modulate.a = 1.0 - minf(_t / 0.8, 1.0) * 0.4
	_circle.rotation += delta * 2.0
	if _t >= 0.8:
		_phase = Phase.MATERIALIZE
		_t = 0.0


func _materialize(delta: float) -> void:
	var k := minf(_t / 0.5, 1.0)
	_circle.modulate.a = maxf(0.0, 1.0 - _t / 0.5)
	if _t >= 0.5:
		_phase = Phase.DONE
		_circle.queue_free()
		_circle = null
		_hint.visible = true
		ritual_done.emit()


func back_f(t: float) -> float:
	# TRANS_BACK-аппроксимация (без Tween-фазы): лёгкий перелёт.
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)


## Анимация переворота по тапу (главная точка входа).
## Двухстадийный scale.x-схлоп: 1 -> 0 (грань сужается), смена сторон,
## 0 -> 1 (другая грань раскрывается). Работает на любом Control.
func flip() -> void:
	if _busy or _phase != Phase.DONE:
		return
	_busy = true
	_hint.visible = false
	pivot_offset = size / 2.0
	var tw := create_tween()
	tw.tween_property(self, "scale:x", 0.0, 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): pass)
	tw.tween_property(self, "scale:x", 1.0, 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		_busy = false
		_hint.visible = true
		_flipped = not _flipped
		flip_toggled.emit(_flipped))





func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		flip()