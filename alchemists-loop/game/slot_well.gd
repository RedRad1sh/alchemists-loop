class_name SlotWell
extends Control
# «Лунка» котла для ингредиента: кольцо + орб внутри (переиспользуем ElementOrb).
# Тап по заполненной лунке очищает её.

signal tapped_clear(well)

var element_id := ""
var _orb: ElementOrb
var _glow := 0.0
var _flash := 0.0
var _tween: Tween
var _ring_col := Color(0.5, 0.6, 0.7, 0.35)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(92, 92)
	resized.connect(_sync_layout)
	# Пустые лунки не требуют собственного кадра.
	set_process(false)

func _sync_layout() -> void:
	pivot_offset = size * 0.5
	if _orb != null and is_instance_valid(_orb) and _orb.visible:
		_orb.position = (size - _orb.size) * 0.5
		_orb.pivot_offset = _orb.size * 0.5

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		# тап по лунке всегда даёт отклик; пустая лунка тоже отвечает (в main)
		tapped_clear.emit(self)

# «Отказ»: короткая вспышка и сжатие — заметно даже на пустой лунке.
func refuse() -> void:
	_flash = 1.0
	set_process(true)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2(1.06, 0.94), 0.05)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK)
	queue_redraw()

func flash() -> void:
	_flash = 0.8
	set_process(true)
	queue_redraw()

func set_slot(item_id: String, col: Color) -> void:
	element_id = item_id
	if element_id == "":
		if _orb != null:
			_orb.queue_free()
			_orb = null
		set_process(false)
		queue_redraw()
		return
	if _orb == null:
		_orb = ElementOrb.new()
		_orb.interactive = false
		_orb.custom_minimum_size = Vector2(66, 66)
		add_child(_orb)
	_orb.setup(item_id, col)
	_glow = 1.0
	set_process(true)
	# «вспышка» при заполнении
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.12, 1.12), 0.08)
	tw.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK)
	queue_redraw()

func _process(delta: float) -> void:
	_glow = maxf(_glow - delta * 2.0, 0.0)
	_flash = maxf(_flash - delta * 2.6, 0.0)
	var layout_settled := true
	var want_pivot := size * 0.5
	if pivot_offset.distance_to(want_pivot) > 0.5:
		pivot_offset = want_pivot
		layout_settled = false
	if _orb != null and _orb.element_id != "" and _orb.visible:
		# держим орб строго по центру лунки (лунка может меняться при раскладке)
		var target_size := Vector2(66, 66)
		if _orb.size != target_size:
			_orb.size = target_size
			layout_settled = false
		var want := (size - _orb.size) * 0.5
		if _orb.position.distance_to(want) > 0.5:
			_orb.position = want
			layout_settled = false
		_orb.pivot_offset = _orb.size * 0.5
		_orb.scale = Vector2.ONE
	if _flash > 0.0:
		queue_redraw()
	if _glow <= 0.0 and _flash <= 0.0 and layout_settled:
		set_process(false)

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 4.0
	draw_circle(c, r, Color(0.04, 0.06, 0.09, 0.8))
	var rc := _ring_col
	if _flash > 0.01:
		rc = _ring_col.lerp(Color(1.0, 0.95, 0.75, 0.9), _flash)
	draw_arc(c, r, 0, TAU, 48, rc, 3.0)
	if _flash > 0.01:
		draw_arc(c, r + 6.0, 0, TAU, 48, Color(1.0, 0.92, 0.7, 0.35 * _flash), 2.0)
	if _glow > 0.01:
		var gc := _orb.orb_color if _orb != null else Color(0.7, 0.8, 0.9)
		draw_arc(c, r + 4.0, 0, TAU, 48, Color(gc.r, gc.g, gc.b, 0.35 * _glow), 3.0)
	# подпись лунки (A/B) внизу
	var f := get_theme_default_font()
	if not has_meta("slot_letter"):
		return
	draw_string(f, c + Vector2(-5, r + 20), str(get_meta("slot_letter")),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.78, 0.82, 0.8))
