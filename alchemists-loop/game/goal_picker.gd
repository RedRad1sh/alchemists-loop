extends RefCounted
class_name GoalPicker
# Модалка §2.1: «По рецепту»/«Эксперимент» → цель (пул пар по слою) → пара.
# z-лестница модалов: dim 20 / center 21 (selftest-инвариант).

const DIM_Z := 20
const CENTER_Z := 21

var g: Game
var _dim: ColorRect = null
var _center: CenterContainer = null
var _body: VBoxContainer = null

func _init(game: Game) -> void:
	g = game

func build() -> void:
	_dim = ColorRect.new()
	_dim.name = "GoalDim"
	_dim.color = Color(0, 0, 0, 0.6)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.z_index = DIM_Z
	_dim.visible = false
	g.add_child(_dim)
	_center = CenterContainer.new()
	_center.name = "GoalCenter"
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_STOP
	_center.z_index = CENTER_Z
	_center.visible = false
	g.add_child(_center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", g._panel_style(Color(0.09, 0.13, 0.19, 0.97), 18))
	_center.add_child(card)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	_body.custom_minimum_size = Vector2(300, 0)
	card.add_child(_body)

func is_open() -> bool:
	return _center != null and _center.visible

func open_mode() -> void:
	_clear()
	_title("Цель варки")
	var b1 := g._small_button("По рецепту", Vector2(0, 46), 1)
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b1.pressed.connect(open_goals)
	_body.add_child(b1)
	var b2 := g._small_button("Эксперимент", Vector2(0, 46), 0)
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b2.pressed.connect(_open_experiment)
	_body.add_child(b2)
	_center.visible = true
	_dim.visible = true

func open_goals() -> void:
	_clear()
	_title("Выбери цель")
	for gm in Game.CIRCLE_GOALS:
		var pool := g._engine._goal_pairs_for(String(gm["key"]))
		var row := VBoxContainer.new()
		var tb := g._small_button("%s · +%d очк." % [String(gm["title"]), int(gm["pts"])], Vector2(0, 46), 2)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.disabled = pool.is_empty()
		if pool.is_empty():
			var hint := g._label("Нет пар такой глубины", 11)
			hint.add_theme_color_override("font_color", Color(0.62, 0.74, 0.82))
			row.add_child(tb)
			row.add_child(hint)
		else:
			tb.pressed.connect(open_pairs.bind(String(gm["key"]), pool))
			row.add_child(tb)
		_body.add_child(row)
	_add_back(open_mode)

func open_pairs(goal_key: String, pool: Array) -> void:
	_clear()
	_title("Пары этой цели (%d)" % pool.size())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	_body.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	for p in pool:
		var pb := g._small_button("%s + %s" % [g._online._item_name(String(p["a"])),
			g._online._item_name(String(p["b"]))], Vector2(0, 44), 0)
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.pressed.connect(_choose_pair.bind(goal_key, String(p["a"]), String(p["b"])))
		col.add_child(pb)
	_add_back(open_goals)

func close() -> void:
	if _center != null:
		_center.visible = false
		_dim.visible = false

func _choose_pair(goal_key: String, a: String, b: String) -> void:
	close()
	g._engine.pending_circle_goal = goal_key
	Analytics.track("circle_goal_chosen", {"goal_depth": goal_key,
		"pool_size": g._engine._goal_pairs_for(goal_key).size()})
	# кладём пару в лунки и варим штатным путём
	g._engine.selected.clear()
	g._engine._place_into_slot(a, "A")
	g._engine._place_into_slot(b, "B")
	g._engine._brew()

func _open_experiment() -> void:
	close()
	# §2.1.3: эксперимент без фильтра цели; существующий пространственный
	# пикер живёт на главной вкладке
	if g._tabs_ref != null:
		g._tabs_ref.current_tab = 0
	g._pages._show_experiment_drawer()

func _clear() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()

func _title(t: String) -> void:
	var lb := g._label(t, 16)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(lb)

func _add_back(fn: Callable) -> void:
	var bb := g._small_button("← Назад", Vector2(0, 40), 0)
	bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bb.pressed.connect(fn)
	_body.add_child(bb)
