class_name HouseView
extends Control
# Домик Светика (вкладка «Дом»), v2: спрайтовая обстановка + живая векторная сцена.
# furniture — Dictionary {категория: item_id}; спрайты грузятся из res://assets/decor/
# и ставятся на якоря ANCHOR (fit-contain в max-размер, привязка к точке).
# Комната (стены/пол/плинтус/половицы) — вектор; Светик — спрайт поверх.
# Свечение берётся из калиброванных FX, а контактная тень рисуется процедурно
# мягким эллипсом: прозрачные поля PNG и старые полосатые shadow-FX не влияют
# на её форму.
# Соло-режим (solo_item != ""): один спрайт крупно — превью в магазине.
# Композиция: три плана (задний у стены ~0.80, средний ~0.90, передний ~0.95),
# стол-герой по центру, камин — самый крупный, дальние предметы чуть темнее.
# Порядок отрисовки (DRAW_ORDER): от заднего плана к переднему.


# Порядок отрисовки: строго от дальнего плана к ближнему для правильного перекрытия (occlusion)
# Ковёр лежит под кроватью и мебелью, поэтому рисуется раньше них.
const DRAW_ORDER := ["window", "shelf", "fireplace", "rug", "bed", "plant", "table", "chair", "lamp"]
# Размер мебели задаётся исходными maxw/maxh и не меняется из-за прозрачных
# полей PNG. Прозрачность учитывается отдельно для hitbox и контактной тени.
const OBJECT_SCALE := 1.0

# Якоря: [ax, ay, maxw, maxh, mode]
# mode: 0 = напольный, 1 = висячий, 2 = настенный
const ANCHOR := {
	"window":   [0.12, 0.08, 0.26, 0.36, 1],  # Окно левее
	"shelf":    [0.55, 0.10, 0.22, 0.28, 1],  # Полка правее и чуть выше
	"fireplace":[0.78, 0.92, 0.40, 0.48, 0],  # Камин: увеличен для пропорциональности (был 0.30, 0.38)
	"rug":      [0.42, 0.82, 0.45, 0.30, 0],  # Ковёр на полу, под кроватью и столом
	"table":    [0.42, 0.88, 0.32, 0.36, 0],  # Стол: чуть увеличен для гармонии со стулом
	"chair":    [0.58, 0.92, 0.28, 0.42, 0],  # Стул: увеличен размер (был 0.20, 0.40), теперь выше стола (спинка)
	"bed":      [0.15, 0.88, 0.34, 0.34, 0],  # Кровать левее и ниже
	"lamp":     [0.72, 0.94, 0.18, 0.34, 0],  # Лампа у камина (вместо парящей)
	"plant":    [0.88, 0.90, 0.14, 0.32, 0],  # Растение в правом углу
}


const HANG := {
	"lamp_4": [0.93, 0.06, 0.15, 0.30],  # фонарь висит у камина
	"lamp_5": [0.62, 0.01, 0.30, 0.22],  # люстра над правой половиной стола
}
# высота напольных торшеров (остальные светильники — настольные/висячие)
const LAMP_H := {"lamp_2": 0.46}
const FLOOR_STANDING := ["shelf_6", "shelf_7"]  # комод и шкаф стоят на полу
const WALL_MOUNT := {"fireplace_6": [0.83, 0.30, 0.36, 0.28]}  # линейный камин — центр на стене (пропорционально увеличен)
const TABLETOP := ["lamp_1", "lamp_3", "lamp_6", "lamp_7", "lamp_8", "lamp_9"]  # малые светильники садятся на стол
const SPRITE_DIR := "res://assets/decor/"
const FX_DIR := "res://assets/decor/fx/"

signal layout_changed(layout: Dictionary)

var house_built := false
var editable := true
var furniture: Dictionary = {}   # категория -> item_id
var _anchor_overrides := {}   # категория -> Vector2(ax, ay) — пользовательские сдвиги
var _drag_cat := ""   # категория, которую перетаскивают
var _drag_start_mouse: Vector2 = Vector2.ZERO   # позиция мыши в пикселях при захвате
var _drag_start_anchor: Vector2 = Vector2.ZERO   # якорь (ax, ay) при захвате
var _drag_start_mode: int = 0   # mode предмета при захвате
var spirit_tex: Texture2D = null
var spirit_aura: Color = Color(1.0, 0.72, 0.36)
var wall_color: Color = Color("#5a4d40")
var floor_color: Color = Color("#5d452f")
var animate := true
var solo_item: String = ""
var _table_ok: bool = false  # стол отрисован в этом кадре (для настольных ламп)
var _table_rect: Rect2 = Rect2()
var _window_ok: bool = false  # окно отрисовано (для светового shaft)
var _window_rect: Rect2 = Rect2()
var _phase: float = 0.0
var _redraw_clock: float = 0.0   # аккумулятор кадров: `_draw` всей сцены дороже одного тика
var _press_layout: Dictionary = {}   # раскладка в момент захвата — эмитим только реальный сдвиг
var _tx_cache: Dictionary = {}  # item_id -> Texture2D (кэш)
var _content_cache: Dictionary = {}  # item_id -> непрозрачная часть PNG в пикселях
var _fx: Dictionary = {}  # fx-имя -> Texture2D (кэш)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if editable else Control.MOUSE_FILTER_IGNORE
	# Первый расчёт гейта: рисовать нужно только видимой и анимируемой сцене.
	set_process(animate and is_visible_in_tree())


func _visibility_changed() -> void:
	# TabContainer прячет неактивные страницы, поэтому уход с вкладки «Дом»
	# приходит сюда, а не в main: на скрытом виде `_draw` жжёт кадры и батарею.
	set_process(animate and is_visible_in_tree())


func set_editable(value: bool) -> void:
	editable = value
	mouse_filter = Control.MOUSE_FILTER_STOP if editable else Control.MOUSE_FILTER_IGNORE


func _gui_input(event: InputEvent) -> void:
	if not editable or not house_built or solo_item != "":
		return
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			var hit := _hit_decor(event.position)
			if not hit.is_empty():
				_drag_cat = String(hit["cat"])
				_drag_start_mouse = event.position
				var item_id: String = String(hit["item_id"])
				_drag_start_mode = _mode_of(item_id)
				var tex_for_anchor: Texture2D = _tex_of(item_id)
				var resolved := _resolved_anchor(_drag_cat, item_id, size.x, size.y, tex_for_anchor)
				_drag_start_anchor = resolved
				if item_id in TABLETOP and _table_ok:
					var tex: Texture2D = _tex_of(item_id)
					if tex != null:
						var r: Rect2 = _tabletop_rect(tex, item_id, size.x, size.y)
						_drag_start_anchor = Vector2(
							(r.position.x + r.size.x * 0.5) / size.x,
							_table_surface_y() / size.y
						)
				# Снимок берётся после посадочных блоков: _tabletop_rect сам
				# доводит якорь настольной лампы до поверхности стола, и это
				# нормальная посадка, а не перетаскивание.
				_press_layout = _layout_data()
				mouse_filter = Control.MOUSE_FILTER_STOP
		else:
			if _drag_cat != "":
				_drag_cat = ""
				mouse_filter = Control.MOUSE_FILTER_STOP if editable else Control.MOUSE_FILTER_IGNORE
				queue_redraw()
				# Отпускание без движения тоже приходило сюда, и home.gd на каждый
				# эмит делал _save_game() + _upload_house(): серийный тап по мебели
				# спамил диск и сеть. Сравниваем раскладку, а не пиксели — возврат
				# предмета на прежнее якорное место не изменение раскладки.
				var released: Dictionary = _layout_data()
				if released != _press_layout:
					layout_changed.emit(released)
	elif event is InputEventMouseMotion and _drag_cat != "":
		var w: float = size.x
		var h: float = size.y
		var cat: String = _drag_cat
		var item_id: String = String(furniture[cat])
		var dx: float = event.position.x - _drag_start_mouse.x
		var dy: float = event.position.y - _drag_start_mouse.y
		var ndx: float = dx / w
		var ndy: float = dy / h
		var new_ax: float = _drag_start_anchor.x + ndx
		var new_ay: float = _drag_start_anchor.y + ndy
		var tex: Texture2D = _tex_of(item_id)
		if tex != null:
			if item_id in TABLETOP and _table_ok:
				# Настольная лампа перемещается по ширине реальной поверхности
				# стола. По высоте она всегда остаётся на поверхности.
				var table_surface := _table_surface_rect()
				var table_sc := _tabletop_scale(tex, h)
				var table_tw := tex.get_width() * table_sc
				var table_min_x := (table_surface.position.x + table_tw * 0.5) / w
				var table_max_x := (table_surface.end.x - table_tw * 0.5) / w
				new_ax = clampf(new_ax, table_min_x, table_max_x)
				new_ay = _table_surface_y() / h
			else:
				# Ограничиваем anchor по реальной видимой части PNG и по типу
				# предмета: пол остаётся полом, стена — стеной, без старого
				# жёсткого диапазона 0.75…0.98.
				var clamped := _clamp_anchor_to_view(cat, item_id, new_ax, new_ay, tex, w, h)
				new_ax = clamped.x
				new_ay = clamped.y
		_anchor_overrides[cat] = Vector2(new_ax, new_ay)
		queue_redraw()


func _hit_decor(pos: Vector2) -> Dictionary:
	# возвращает {cat, item_id} первой (верхней в DRAW_ORDER) мебели под курсором; {} если ничего
	for i in range(DRAW_ORDER.size() - 1, -1, -1):
		var cat: String = String(DRAW_ORDER[i])
		if not furniture.has(cat):
			continue
		var item_id: String = String(furniture[cat])
		var w: float = size.x
		var h: float = size.y
		var r: Rect2 = _item_rect(cat, item_id, w, h)
		# Захватываем только видимую часть PNG, а не прозрачное поле вокруг неё.
		if _visual_rect(item_id, r).has_point(pos):
			return {"cat": cat, "item_id": item_id}
	return {}


func _tex_of(item_id: String) -> Texture2D:
	if _tx_cache.has(item_id):
		return _tx_cache[item_id]
	var t: Texture2D = load(SPRITE_DIR + item_id + ".png") as Texture2D
	_tx_cache[item_id] = t
	return t


func _content_rect(item_id: String, tex: Texture2D) -> Rect2:
	if _content_cache.has(item_id):
		return _content_cache[item_id]
	var image := tex.get_image()
	if image == null:
		var full := Rect2(0.0, 0.0, tex.get_width(), tex.get_height())
		_content_cache[item_id] = full
		return full
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	# Alpha ниже 0.12 — это антиалиасинг/почти прозрачная тень в полях.
	# Она не должна становиться частью hitbox или опорной точки тени.
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a >= 0.12:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x + 1)
				max_y = maxi(max_y, y + 1)
	if max_x < 0 or max_y < 0:
		var fallback := Rect2(0.0, 0.0, tex.get_width(), tex.get_height())
		_content_cache[item_id] = fallback
		return fallback
	var used := Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
	_content_cache[item_id] = used
	return used


func _visual_rect(item_id: String, r: Rect2) -> Rect2:
	var tex := _tex_of(item_id)
	if tex == null:
		return r
	var used := _content_rect(item_id, tex)
	var sx := r.size.x / float(tex.get_width())
	var sy := r.size.y / float(tex.get_height())
	return Rect2(
		r.position.x + used.position.x * sx,
		r.position.y + used.position.y * sy,
		used.size.x * sx,
		used.size.y * sy
	)


func _clamp_anchor_to_view(cat: String, item_id: String, ax: float, ay: float,
		tex: Texture2D, w: float, h: float) -> Vector2:
	if w <= 0.0 or h <= 0.0:
		return Vector2(ax, ay)
	var p: Array = _anchor_params(cat, item_id)
	var mw: float = p[2]
	var mh: float = p[3]
	var sc: float = minf(mw * w / tex.get_width(), mh * h / tex.get_height()) * OBJECT_SCALE
	var tw := tex.get_width() * sc
	var th := tex.get_height() * sc
	var used := _content_rect(item_id, tex)
	var used_x0 := used.position.x * sc
	var used_y0 := used.position.y * sc
	var used_x1 := used.end.x * sc
	var used_y1 := used.end.y * sc
	var ax_min := (tw * 0.5 - used_x0) / w
	var ax_max := (w + tw * 0.5 - used_x1) / w
	var mode := _mode_of(item_id)
	var wall_h := h * 0.60
	var ay_min: float
	var ay_max: float
	if mode == 1:
		# Висячие/задние предметы остаются в зоне стены.
		ay_min = -used_y0 / h
		ay_max = (wall_h - used_y1) / h
	elif mode == 2:
		# Настенные предметы: их видимая часть не проваливается на пол.
		ay_min = (th * 0.5 - used_y0) / h
		ay_max = (wall_h + th * 0.5 - used_y1) / h
	else:
		# Напольные предметы: основание не поднимается на стену, но
		# прозрачное поле снизу не мешает опустить видимую часть до пола.
		ay_min = (wall_h + th - used_y1) / h
		ay_max = (h + th - used_y1) / h
	if ay_min > ay_max:
		var ay_mid := (ay_min + ay_max) * 0.5
		ay_min = ay_mid
		ay_max = ay_mid
	return Vector2(clampf(ax, ax_min, ax_max), clampf(ay, ay_min, ay_max))


func _resolved_anchor(cat: String, item_id: String, w: float, h: float, tex: Texture2D) -> Vector2:
	var p: Array = _anchor_params(cat, item_id)
	var safe := _clamp_anchor_to_view(cat, item_id, float(p[0]), float(p[1]), tex, w, h)
	if _anchor_overrides.has(cat):
		# Самовосстановление старых сейвов, в которых предмет уже был
		# унесён за пределы экрана предыдущим clamp.
		_anchor_overrides[cat] = safe
	return safe


func _item_rect(cat: String, item_id: String, w: float, h: float) -> Rect2:
	var tex: Texture2D = _tex_of(item_id)
	if tex == null:
		return Rect2()
	if item_id in TABLETOP and _table_ok:
		return _tabletop_rect(tex, item_id, w, h)
	var mode: int = _mode_of(item_id)
	var params: Array = _anchor_params(cat, item_id)
	var anchor := _resolved_anchor(cat, item_id, w, h, tex)
	var ax: float = anchor.x
	var ay: float = anchor.y
	var mw: float = params[2]
	var mh: float = params[3]
	var sc: float = minf(mw * w / tex.get_width(), mh * h / tex.get_height()) * OBJECT_SCALE
	var tw: float = tex.get_width() * sc
	var th: float = tex.get_height() * sc
	var dx: float = ax * w - tw * 0.5
	var dy: float
	if mode == 1:
		dy = ay * h
	elif mode == 2:
		dy = ay * h - th * 0.5
	else:
		dy = ay * h - th
	return Rect2(dx, dy, tw, th)


func _mode_of(item_id: String) -> int:
	if HANG.has(item_id):
		return 1
	if WALL_MOUNT.has(item_id):
		return 2
	if item_id in FLOOR_STANDING:
		return 0
	var cat: String = _cat_of(item_id)
	var a: Array = ANCHOR.get(cat, [0.5, 0.9, 0.2, 0.3, 0])
	return int(a[4])


func _mw_of(item_id: String) -> float:
	if HANG.has(item_id):
		return HANG[item_id][2]
	if WALL_MOUNT.has(item_id):
		return WALL_MOUNT[item_id][2]
	if item_id in FLOOR_STANDING:
		return 0.30
	var cat: String = _cat_of(item_id)
	var a: Array = ANCHOR.get(cat, [0.5, 0.9, 0.2, 0.3, 0])
	return a[2]


func _mh_of(item_id: String) -> float:
	if HANG.has(item_id):
		return HANG[item_id][3]
	if WALL_MOUNT.has(item_id):
		return WALL_MOUNT[item_id][3]
	if item_id in FLOOR_STANDING:
		return 0.55
	var cat: String = _cat_of(item_id)
	if cat == "lamp":
		return LAMP_H.get(item_id, 0.34)
	var a: Array = ANCHOR.get(cat, [0.5, 0.9, 0.2, 0.3, 0])
	return a[3]


func _cat_of(item_id: String) -> String:
	for cat in DRAW_ORDER:
		if furniture.has(cat) and String(furniture[cat]) == item_id:
			return cat
	return "misc"


func _anchor_params(cat: String, item_id: String) -> Array:
	var ax: float
	var ay: float
	var mw: float
	var mh: float
	if HANG.has(item_id):
		var hg: Array = HANG[item_id]
		ax = hg[0]
		ay = hg[1]
		mw = hg[2]
		mh = hg[3]
	elif WALL_MOUNT.has(item_id):
		var wm: Array = WALL_MOUNT[item_id]
		ax = wm[0]
		ay = wm[1]
		mw = wm[2]
		mh = wm[3]
	else:
		var a: Array = ANCHOR.get(cat, [0.5, 0.9, 0.2, 0.3, 0])
		ax = a[0]
		ay = a[1]
		mw = a[2]
		mh = a[3]
		if item_id in FLOOR_STANDING:
			ax = 0.10
			ay = 0.90
			mw = 0.30
			mh = 0.55
		if cat == "lamp":
			mh = LAMP_H.get(item_id, 0.34)
	if _anchor_overrides.has(cat):
		var ov: Vector2 = _anchor_overrides[cat]
		ax = ov.x
		ay = ov.y
	return [ax, ay, mw, mh]


func set_state(built: bool, furn: Dictionary, tex: Texture2D,
		aura: Color = Color(1.0, 0.72, 0.36),
		wall: Color = Color("#5a4d40"), floor: Color = Color("#5d452f"),
		layout: Dictionary = {}) -> void:
	house_built = built
	furniture = furn.duplicate()
	spirit_tex = tex
	spirit_aura = aura
	wall_color = wall
	floor_color = floor
	solo_item = ""
	_apply_layout(layout)
	queue_redraw()


func _apply_layout(layout: Dictionary) -> void:
	_anchor_overrides = {}
	for raw_cat in layout:
		var cat := String(raw_cat)
		if not furniture.has(cat):
			continue
		var raw_pos = layout[raw_cat]
		if raw_pos is Array and raw_pos.size() >= 2:
			# Прозрачное поле может требовать anchor чуть за 0…1,
			# чтобы видимая часть действительно доходила до края комнаты.
			var ax := clampf(float(raw_pos[0]), -0.25, 1.25)
			var ay := clampf(float(raw_pos[1]), -0.25, 1.25)
			_anchor_overrides[cat] = Vector2(ax, ay)
		elif raw_pos is Vector2:
			var pos: Vector2 = raw_pos
			_anchor_overrides[cat] = Vector2(clampf(pos.x, -0.25, 1.25), clampf(pos.y, -0.25, 1.25))


func _layout_data() -> Dictionary:
	var out := {}
	for raw_cat in _anchor_overrides:
		var cat := String(raw_cat)
		var pos: Vector2 = _anchor_overrides[cat]
		out[cat] = [pos.x, pos.y]
	return out


func set_solo(item_id: String) -> void:
	solo_item = item_id
	queue_redraw()


func _process(delta: float) -> void:
	if not animate:
		# animate выключают присваиванием поля (home.gd: thumb.animate = false),
		# когда process уже был включён: паркуемся здесь же, на первом тике.
		set_process(false)
		return
	if not is_visible_in_tree():
		# страховка за _visibility_changed: у скрытого вида рисовать нечего
		set_process(false)
		return
	_phase += delta
	_redraw_clock += delta
	# Кадры режем до ~20 к/с (как cauldron_view): фаза копится по delta, поэтому
	# анимация остаётся синхронной по времени, а `_draw` всей процедурной комнаты
	# вызывается заметно реже.
	if _redraw_clock >= 0.05:
		_redraw_clock = 0.0
		queue_redraw()


# ---------- примитивы ----------

func _grad(r: Rect2, top: Color, bot: Color) -> void:
	var steps: int = 9
	for i in steps:
		var t: float = float(i) / float(steps - 1)
		var hh: float = r.size.y / float(steps)
		draw_rect(Rect2(r.position.x, r.position.y + i * hh, r.size.x, hh + 0.6), top.lerp(bot, t))


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 25:
		var a: float = TAU * float(i) / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


# ---------- сцена ----------

func _draw() -> void:
	if solo_item != "":
		_draw_solo()
		return
	var w: float = size.x
	var h: float = size.y
	var wall_h: float = h * 0.60
	# стена и пол (цвета могут быть произвольными)
	_grad(Rect2(0, 0, w, wall_h), wall_color.lightened(0.06), wall_color.darkened(0.14))
	_grad(Rect2(0, wall_h, w, h - wall_h), floor_color.lightened(0.05), floor_color.darkened(0.18))
	# плинтус
	draw_rect(Rect2(0, wall_h - h * 0.015, w, h * 0.02), Color(0, 0, 0, 0.30))
	# половицы
	var plank: Color = Color(0, 0, 0, 0.12)
	for i in 5:
		var py: float = wall_h + (h - wall_h) * (0.16 + 0.16 * i)
		draw_line(Vector2(0, py), Vector2(w, py), plank, 1.0)

	if not house_built:
		_draw_plot(w, h, wall_h)
		return

	_table_ok = false
	_window_ok = false
	_window_rect = _place_window(w, h)
	_draw_shaft_from_window(w, h)
	for cat in DRAW_ORDER:
		if not furniture.has(cat):
			continue
		_draw_item(String(cat), String(furniture[cat]), w, h)
	_draw_atmosphere(w, h)
	_draw_spirit(w, h)
	_draw_dust(w, h)


func _draw_solo() -> void:
	var tex: Texture2D = _tex_of(solo_item)
	if tex == null:
		return
	var pad: float = 6.0
	var sc: float = minf((size.x - pad * 2.0) / tex.get_width(), (size.y - pad * 2.0) / tex.get_height())
	var tw: float = tex.get_width() * sc
	var th: float = tex.get_height() * sc
	var r: Rect2 = Rect2((size.x - tw) * 0.5, (size.y - th) * 0.5, tw, th)
	draw_texture_rect(tex, r, false)
	_fx_glow(solo_item, r)


func _draw_plot(w: float, h: float, wall_h: float) -> void:
	# пустой участок: трава/земля и невысокий забор
	_grad(Rect2(0, wall_h, w, h - wall_h), Color("#3c2f22"), Color("#2c2117"))
	for i in 9:
		var x: float = w * 0.06 + i * (w * 0.88 / 8.0)
		draw_rect(Rect2(x, wall_h + (h - wall_h) * 0.14, w * 0.014, (h - wall_h) * 0.30), Color("#4a3a2a"))
	draw_rect(Rect2(w * 0.03, wall_h + (h - wall_h) * 0.24, w * 0.94, w * 0.016), Color("#4a3a2a"))
	draw_rect(Rect2(w * 0.03, wall_h + (h - wall_h) * 0.34, w * 0.94, w * 0.010), Color("#3c2f22"))


func _draw_spirit(w: float, h: float) -> void:
	if spirit_tex == null:
		return
	var bob: float = sin(_phase * 1.6) * 5.0
	var sx: float = w * 0.50 + sin(_phase * 0.7) * w * 0.18
	var sy: float = h * 0.40 + bob
	var ga: Color = spirit_aura
	draw_circle(Vector2(sx, sy), 34.0, Color(ga.r, ga.g, ga.b, 0.10))
	draw_circle(Vector2(sx, sy), 20.0, Color(ga.r, ga.g, ga.b, 0.20))
	var sc: float = minf(70.0 / spirit_tex.get_width(), 64.0 / spirit_tex.get_height())
	var tw: float = spirit_tex.get_width() * sc
	var th: float = spirit_tex.get_height() * sc
	draw_texture_rect(spirit_tex, Rect2(sx - tw * 0.5, sy - th * 0.5, tw, th), false)


# ---------- обстановка ----------

func _draw_item(cat: String, item_id: String, w: float, h: float) -> void:
	var tex: Texture2D = _tex_of(item_id)
	if tex == null:
		return
	if item_id in TABLETOP and _table_ok:
		_place_tabletop(tex, item_id, w, h)
		return
	var mode: int = _mode_of(item_id)
	var p: Array = _anchor_params(cat, item_id)
	var anchor := _resolved_anchor(cat, item_id, w, h, tex)
	var ax: float = anchor.x
	var ay: float = anchor.y
	var mw: float = p[2]
	var mh: float = p[3]
	var sc: float = minf(mw * w / tex.get_width(), mh * h / tex.get_height()) * OBJECT_SCALE
	var tw: float = tex.get_width() * sc
	var th: float = tex.get_height() * sc
	var dx: float = ax * w - tw * 0.5
	var dy: float
	if mode == 1:
		dy = ay * h
	elif mode == 2:
		dy = ay * h - th * 0.5
	else:
		dy = ay * h - th
	var r: Rect2 = Rect2(dx, dy, tw, th)
	if cat == "table":
		_table_rect = r
		_table_ok = true
	_fx_shadow(item_id, r)
	var dim: float = 1.0
	if mode == 1:
		dim = 0.92
	elif mode == 0:
		dim = 0.90 + 0.10 * clampf((ay - 0.78) / 0.17, 0.0, 1.0)
	draw_texture_rect(tex, r, false, Color(dim, dim, dim))
	_fx_glow(item_id, r)


func _table_surface_rect() -> Rect2:
	if not furniture.has("table"):
		return _table_rect
	var table_id := String(furniture["table"])
	var table_tex := _tex_of(table_id)
	if table_tex == null:
		return _table_rect
	return _visual_rect(table_id, _table_rect)


func _table_surface_y() -> float:
	# Верхняя кромка реального стола, а не верх прозрачного PNG-поля.
	return _table_surface_rect().position.y + 4.0


func _tabletop_scale(tex: Texture2D, h: float) -> float:
	return minf(_table_rect.size.x * 0.30 * OBJECT_SCALE / tex.get_width(),
		h * 0.20 * OBJECT_SCALE / tex.get_height())


func _tabletop_rect(tex: Texture2D, item_id: String, _w: float, h: float) -> Rect2:
	var sc: float = _tabletop_scale(tex, h)
	var tw: float = tex.get_width() * sc
	var th: float = tex.get_height() * sc
	var cat := _cat_of(item_id)
	var table_surface := _table_surface_rect()
	var default_spot: float = table_surface.position.x + table_surface.size.x * 0.72
	var min_spot: float = table_surface.position.x + tw * 0.5
	var max_spot: float = table_surface.end.x - tw * 0.5
	if max_spot < min_spot:
		max_spot = min_spot
	var spot: float = default_spot
	if _anchor_overrides.has(cat):
		spot = _anchor_overrides[cat].x * _w
	spot = clampf(spot, min_spot, max_spot)
	# Высота настольной лампы никогда не берётся из старого layout:
	# при смене стола она заново садится на его текущую поверхность.
	var surface_y: float = _table_surface_y()
	if _anchor_overrides.has(cat):
		_anchor_overrides[cat] = Vector2(spot / _w, surface_y / h)
	# Якорь — низ видимой части лампы. Поэтому прозрачное поле снизу
	# больше не оставляет лампу «висящей» над столом.
	var used := _content_rect(item_id, tex)
	var visible_bottom_offset := used.end.y * sc
	return Rect2(spot - tw * 0.5, surface_y - visible_bottom_offset, tw, th)


func _place_tabletop(tex: Texture2D, item_id: String, w: float, h: float) -> void:
	var r: Rect2 = _tabletop_rect(tex, item_id, w, h)
	_fx_shadow(item_id, r)
	draw_texture_rect(tex, r, false)
	_fx_glow(item_id, r)


func _fx_of(fx_name: String) -> Texture2D:
	if _fx.has(fx_name):
		return _fx[fx_name]
	var t: Texture2D = load(FX_DIR + fx_name + ".png") as Texture2D
	_fx[fx_name] = t
	return t


func _fx_rect(r: Rect2, f: Array) -> Rect2:
	return Rect2(r.position.x + f[0] * r.size.x, r.position.y + f[1] * r.size.y,
		(f[2] - f[0]) * r.size.x, (f[3] - f[1]) * r.size.y)


func _fx_shadow(item_id: String, r: Rect2) -> void:
	# Рисуем тень от фактической непрозрачной части PNG. Полный canvas
	# у bed/table/fireplace заметно шире и выше рисунка, из-за чего старая
	# тень уезжала вправо и вниз.
	if item_id == "rug":
		return
	if item_id not in TABLETOP and _mode_of(item_id) != 0:
		return
	var vr := _visual_rect(item_id, r)
	var rx := vr.size.x * (0.46 if item_id == "bed" else 0.42)
	var ry := clampf(vr.size.y * 0.035, 2.0, 7.0)
	var c := Vector2(vr.position.x + vr.size.x * 0.5, vr.end.y - ry * 0.18)
	_ellipse(c, rx * 1.12, ry * 1.45, Color(0.0, 0.0, 0.0, 0.030))
	_ellipse(c, rx * 0.90, ry * 1.05, Color(0.0, 0.0, 0.0, 0.050))
	_ellipse(c, rx * 0.64, ry * 0.72, Color(0.0, 0.0, 0.0, 0.070))


func _glow_mod(item_id: String) -> Color:
	var is_fire: bool = item_id == "fireplace" or item_id.begins_with("fireplace_")
	var flick: float = 0.15 + 0.05 * sin(_phase * 9.0)
	if not is_fire:
		var pulse: float = 0.5 + 0.5 * sin(_phase * 2.4)
		flick = 0.10 + 0.06 * pulse
	var tint: Color = Color(1.0, 0.62, 0.25)
	var e: Dictionary = DecorCalib.CALIB.get(item_id, {})
	if e.has("tint"):
		var tc: Array = e["tint"]
		tint = Color(tc[0], tc[1], tc[2])
	return Color(tint.r, tint.g, tint.b, flick * 2.0)


func _fx_glow(item_id: String, r: Rect2) -> void:
	var e: Dictionary = DecorCalib.CALIB.get(item_id, {})
	if not e.has("glow_fx"):
		return
	var d: Dictionary = e["glow_fx"]
	var t: Texture2D = _fx_of(String(d["tex"]))
	if t == null:
		return
	draw_texture_rect(t, _fx_rect(r, d["rect"]), false, _glow_mod(item_id))

# ---------- атмосфера ----------

func _draw_atmosphere(w: float, h: float) -> void:
	# дневной тон: тёплая вуаль сверху, к полу сходит на нет
	_grad(Rect2(0, 0, w, h), Color(1.0, 0.96, 0.88, 0.07), Color(1.0, 0.96, 0.88, 0.0))


func _place_window(w: float, h: float) -> Rect2:
	if not furniture.has("window"):
		return Rect2()
	var item_id: String = String(furniture["window"])
	var tex: Texture2D = _tex_of(item_id)
	if tex == null:
		return Rect2()
	var mode: int = _mode_of(item_id)
	var p: Array = _anchor_params("window", item_id)
	var anchor := _resolved_anchor("window", item_id, w, h, tex)
	var ax: float = anchor.x
	var ay: float = anchor.y
	var mw: float = p[2]
	var mh: float = p[3]
	var sc: float = minf(mw * w / tex.get_width(), mh * h / tex.get_height()) * OBJECT_SCALE
	var tw: float = tex.get_width() * sc
	var th: float = tex.get_height() * sc
	var dx: float = ax * w - tw * 0.5
	var dy: float
	if mode == 1:
		dy = ay * h
	elif mode == 2:
		dy = ay * h - th * 0.5
	else:
		dy = ay * h - th
	_window_ok = true
	return Rect2(dx, dy, tw, th)


func _draw_shaft_from_window(w: float, h: float) -> void:
	# shaft из реального стекла (широкое слабое + узкое ядро), за мебелью
	if not _window_ok:
		return
	var wid: String = String(furniture.get("window", ""))
	var e: Dictionary = DecorCalib.CALIB.get(wid, {})
	if not e.has("glass"):
		return
	var gg: Array = e["glass"]
	var r: Rect2 = _window_rect
	var gy: float = r.position.y + r.size.y * (gg[1] + gg[3]) * 0.5
	var gx0: float = r.position.x + r.size.x * lerpf(gg[0], gg[2], 0.15)
	var gx1: float = r.position.x + r.size.x * lerpf(gg[0], gg[2], 0.85)
	var y1: float = h * 0.995
	var slant: float = w * 0.13
	var widen: float = (gx1 - gx0) * 0.15
	draw_colored_polygon(PackedVector2Array([
		Vector2(gx0, gy), Vector2(gx1, gy),
		Vector2(gx1 + slant + widen, y1), Vector2(gx0 + slant - widen, y1)]),
		Color(1.0, 0.95, 0.80, 0.045))
	var inset: float = (gx1 - gx0) * 0.25
	draw_colored_polygon(PackedVector2Array([
		Vector2(gx0 + inset, gy), Vector2(gx1 - inset, gy),
		Vector2(gx1 - inset + slant, y1), Vector2(gx0 + inset + slant, y1)]),
		Color(1.0, 0.95, 0.80, 0.05))
	_ellipse(Vector2((gx0 + gx1) * 0.5 + slant, h * 0.965),
		(gx1 - gx0) * 0.5 + widen, h * 0.022, Color(1.0, 0.95, 0.80, 0.06))


func _draw_dust(w: float, h: float) -> void:
	for i in 14:
		var fx: float = fmod(float(i) * 0.377 + 0.13, 1.0)
		var spd: float = 6.0 + float(i % 5) * 2.2
		var yy: float = fmod(float(i) * 53.0 + _phase * spd, h)
		var xx: float = w * fx + sin(_phase * 0.6 + float(i) * 1.7) * 8.0
		var tw: float = 0.5 + 0.5 * sin(_phase * 1.9 + float(i) * 2.3)
		draw_circle(Vector2(xx, yy), 1.2 + float(i % 3) * 0.5,
			Color(1.0, 0.98, 0.92, 0.05 + 0.06 * tw))
