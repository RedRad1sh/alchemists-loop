class_name SigilCard
extends Control

## Сборка всех слоёв карточки в один узел. Порядок снизу вверх:
##   1 FluidArt      — фон
##   2 AuraView      — аура редкости
##   3 CircleView    — трансмутационный круг (кольца, глифы, слоты)
##   4 IconView      — центральный объект
##   5 FrameView     — рамка
##   6 Label         — название
##
## Один и тот же экземпляр переиспользуется рендер-сервисом, поэтому
## карточка умеет только пересобираться (setup), но не плодит поддеревья.

signal setup_done(card: SigilCard)

var recipe: SigilRecipe
var options: SigilOptions
var seed_value: int = 0
var layout: SigilCircleLayout
var palette: SigilPalette
var icon_ctx: Dictionary = {}

## Живой режим: включается только для карточки в игре (SubViewport
## с UPDATE_ALWAYS). В статичном рендере (превью, кэш, Python-эталон)
## остаётся false — слои стоят ровно, PNG совпадает до пикселя.
var live_mode := false
var _time := 0.0
var _tilt := Vector2.ZERO
var _tilt_target := Vector2.ZERO

## Параллакс-сдвиг декоративных слоёв. IconView в этот список НЕ входит:
## у него своя внутренняя анимация, любое вмешательство в его transform
## ломает её (иконка «перегенерируется» / крутится рывками).
const PARALLAX_PX := 10.0

var bg: SigilFluidBg
var prism: ColorRect  # Prism-эффект (превью); null когда выключен
var aura: SigilAuraView
var circle: SigilCircleView
var foil: SigilFinishView
var icon: SigilIconView
var sparkles: SigilFinishView
var frame: SigilFrameView
var glitch: SigilGlitchView
var title: Label


func setup(p_recipe: SigilRecipe, p_options: SigilOptions) -> void:
	recipe = p_recipe
	options = p_options
	seed_value = recipe.compute_seed()
	palette = SigilPalette.make(seed_value, recipe.rarity)

	custom_minimum_size = options.effective_size()
	size = options.effective_size()
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var cr := options.circle_rect()
	layout = SigilCircleLayout.build(seed_value, recipe, cr.get_center(), cr.size.x * 0.5, options)
	icon_ctx = build_icon_ctx(seed_value, recipe, options, palette)

	_ensure_nodes()
	_place_nodes(cr)
	_refresh()
		# Фон получает флаг живого режима — дрожит только в игре, в статичном
	# рендере phase заморожен на seed-значении.
	if bg != null:
		bg.set_live(live_mode)
	setup_done.emit(self)


func _ensure_nodes() -> void:
	if bg == null:
		bg = SigilFluidBg.new()
		bg.name = "FluidArt"
		add_child(bg)
	if prism == null:
		prism = ColorRect.new()
		prism.name = "Prism"
		prism.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(prism)
	if aura == null:
		aura = SigilAuraView.new()
		aura.name = "Aura"
		add_child(aura)
	if foil == null:
		foil = SigilFinishView.new()
		foil.name = "Foil"
		foil.part = SigilFinishView.Part.FOIL
		add_child(foil)
	if circle == null:
		circle = SigilCircleView.new()
		circle.name = "Circle"
		add_child(circle)
	if icon == null:
		icon = SigilIconView.new()
		icon.name = "Icon"
		add_child(icon)
	if sparkles == null:
		sparkles = SigilFinishView.new()
		sparkles.name = "Sparkles"
		sparkles.part = SigilFinishView.Part.SPARKLES
		add_child(sparkles)
	if frame == null:
		frame = SigilFrameView.new()
		frame.name = "Frame"
		add_child(frame)
	if title == null:
		title = Label.new()
		title.name = "Title"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
		title.add_theme_constant_override("outline_size", 6)
		add_child(title)
	if glitch == null:
		glitch = SigilGlitchView.new()
		glitch.name = "Glitch"
		add_child(glitch)


func _place_nodes(cr: Rect2) -> void:
	var s := options.effective_size()
	for c in [bg, prism, aura, foil, circle, sparkles, frame]:
		(c as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
		(c as Control).position = Vector2.ZERO
		(c as Control).size = s
	glitch.set_anchors_preset(Control.PRESET_FULL_RECT)
	glitch.position = Vector2.ZERO
	glitch.size = s

	var icon_d := layout.icon_radius * 2.0
	icon.position = layout.icon_center() - Vector2(icon_d, icon_d) * 0.5
	icon.size = Vector2(icon_d, icon_d)

	icon.visible = options.show_icon
	title.visible = options.show_name
	title.text = options.name_text if options.name_text != "" else String(recipe.display_name)
	title.add_theme_font_size_override("font_size", options.name_font_size)
	title.add_theme_color_override("font_color", palette.ink)
	# Подпись живёт в полосе от SigilOptions, а не по своей формуле:
	# иначе рамка и надпись разъезжаются по вертикали.
	var band := options.title_rect()
	title.position = band.position
	title.size = band.size


func _refresh() -> void:
	bg.setup(options, palette, seed_value)
	_setup_prism()
	aura.setup(options, palette, layout.center, layout.radius, seed_value)
	foil.setup(SigilFinishView.Part.FOIL, options, palette, seed_value,
		layout.icon_center(), layout.radius)
	circle.setup(layout, palette, options)
	sparkles.setup(SigilFinishView.Part.SPARKLES, options, palette, seed_value,
		layout.icon_center(), layout.radius)
	if options.show_icon:
		icon.setup(SigilGeneratorRegistry.get_generator(recipe.result_type), icon_ctx,
			SigilRng.new(seed_value).fork("icon"), palette.ink, palette.accent)
	frame.setup(options, palette, seed_value)
	glitch.setup(palette.glitch, seed_value)
	queue_redraw()


# ────────────────────────────────────────────────────────────────────────────
# Живой режим: параллакс фоновых слоёв и каскад появления.
# IconView намеренно исключён из всех эффектов: у него своя внутренняя
# анимация (форма/поворот/масштаб), и любая запись из родителя её ломает —
# иконка начинает «перегенерироваться» по нескольку раз в секунду.
# ────────────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not live_mode:
		return
	_time += delta
	_tilt = _tilt.lerp(_tilt_target, clampf(delta * 7.0, 0.0, 1.0))
	_apply_parallax()
	# Prism-эффекты анимируются фазой по времени (сдвиг панхроматики/глитча/масла).
	if prism != null and prism.visible and prism.material != null:
		(prism.material as ShaderMaterial).set_shader_parameter(
			"phase", Time.get_ticks_msec() / 1000.0)


## Нормализованный вектор наклона: -1..1 по X и Y. Вызывается из _process
## игры по позиции курсора относительно центра экрана.
func set_tilt(normalized: Vector2) -> void:
	_tilt_target = Vector2(
		clampf(normalized.x, -1.0, 1.0),
		clampf(normalized.y, -1.0, 1.0))


## Каскадное появление: слои проявляются по очереди с лёгким scale-in из
## центра. Иконка и заголовок не входят — они появляются вместе с карточкой,
## как только фуллскрин открылся.
func play_reveal() -> void:
	if not live_mode:
		return
	var ordered: Array = []
	for n in [bg, aura, foil, circle, sparkles, frame]:
		var c := n as Control
		if c == null or not c.visible:
			continue
		ordered.append(c)

	for c in ordered:
		(c as Control).modulate.a = 0.0
	var tw := create_tween().set_parallel()
	var delay := 0.0
	for c in ordered:
		var node := c as Control
		node.pivot_offset = node.size * 0.5
		node.scale = Vector2(0.90, 0.90)
		tw.tween_property(node, "modulate:a", 1.0, 0.30).set_delay(delay)
		tw.tween_property(node, "scale", Vector2.ONE, 0.42)\
			.set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		delay += 0.07


## Параллакс-тилт: передние слои сдвигаются сильнее фоновых. Фон, аура,
## рамка, заголовок и иконка не двигаются вовсе — иначе по краям
## SubViewport открывалась бы дыра, а иконка шла бы рывками от конфликта
## с собственной анимацией.
func _apply_parallax() -> void:
	var d := PARALLAX_PX
	foil.position     = _tilt * d * 0.30
	circle.position   = _tilt * d * 0.45
	sparkles.position = _tilt * d * 0.55


## Контекст для генератора центрального объекта. Свойства рецепта
## пробрасываются верхним уровнем (их видит и генератор, и будущие расширения),
## палитра иконки выводится из палитры карточки.
##
## Статическая функция, а не метод: её зовёт и карточка, и отдельный
## экспорт центрального элемента (SigilRenderService.render_icon). Одна
## функция — значит вытащенная иконка не может разойтись с карточкой.
static func build_icon_ctx(seed_value: int, recipe: SigilRecipe,
		options: SigilOptions, palette: SigilPalette) -> Dictionary:
	var rng := SigilRng.new(seed_value).fork("iconctx")
	var ctx: Dictionary = {
		"seed": seed_value,
		"rarity": recipe.rarity,
		"pixel_grid": options.pixel_grid,
		"properties": recipe.properties.duplicate(true),
	}
	for k in recipe.properties.keys():
		ctx[str(k)] = recipe.properties[k]

	var ip: Dictionary = {}
	if recipe.properties.has("icon_palette") and typeof(recipe.properties["icon_palette"]) == TYPE_DICTIONARY:
		ip = (recipe.properties["icon_palette"] as Dictionary).duplicate(true)
	else:
		var h := fposmod(palette.aura_color.h + rng.randf_range(-0.12, 0.12), 1.0)
		var body := Color.from_hsv(h, rng.randf_range(0.30, 0.75), rng.randf_range(0.45, 0.88))
		ip = {
			"body": body,
			"ink": palette.ink,
			"accent": palette.accent,
			"belly": body.lerp(Color(1, 1, 1), 0.5),
			"deep": body.lerp(Color(0.05, 0.08, 0.16), 0.7),
			"shallow": body.lerp(Color(0.4, 0.7, 0.9), 0.5),
			"land": body.lerp(Color(0.35, 0.55, 0.3), 0.55),
			"high": Color(0.85, 0.88, 0.85),
			"ice": Color(0.92, 0.96, 1.0),
			"atmosphere": palette.aura_color.lerp(Color(0.7, 0.85, 1.0), 0.55),
			"ring": body.lerp(Color(0.9, 0.92, 0.95), 0.5),
		}
	ctx["icon_palette"] = ip
	return ctx


func set_debug_slots(v: bool) -> void:
	circle.set_debug_slots(v)
	circle.queue_redraw()


## Prism-превью: кладёт поверх фона canvas_item-шейдер из пакета card_beatify.
## Только для контакт-листа — в релизном рендере options.prism_effect пуст,
## узел скрыт и в кэш не влияет.
func _setup_prism() -> void:
	if prism == null:
		return
	var eff := String(options.prism_effect).strip_edges()
	if eff == "":
		prism.visible = false
		prism.material = null
		return
	var sh := load("res://game/sigil/shaders/prism/%s.gdshader" % eff)
	if sh == null:
		prism.visible = false
		prism.material = null
		return
	# galaxy — надстройка ПОД кругом/объектом (сразу после фона);
	# остальные — текстура ПОВЕРХ карты (последний слой).
	if eff == "galaxy":
		move_child(prism, 1)  # [bg, prism, aura, circle, ...]
	else:
		move_child(prism, get_child_count() - 1)  # поверх frame/title
	# Статичная фаза из seed (PNG детерминирован) либо явная из опций (анимации).
	var ph := options.prism_phase
	if ph < 0.0:
		ph = float(seed_value % 1000) / 1000.0
	var mat := ShaderMaterial.new()
	mat.shader = sh
	prism.material = mat
	prism.visible = true
	prism.color = Color(1, 1, 1, 1)
	prism.self_modulate.a = 1.0
	# Параметры ПОСЛЕ назначения material — иначе Godot может не применить их
	# к свежему ShaderMaterial на CanvasItem.
	mat.set_shader_parameter("phase", ph)
	prism.queue_redraw()
	
	
# В SigilCard.gd
func set_live(v: bool) -> void:
	live_mode = v
	set_process(v)
	if bg != null:
		bg.set_live(v)