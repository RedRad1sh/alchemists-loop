class_name SigilCard
extends Control

signal setup_done(card: SigilCard)

var recipe: SigilRecipe
var options: SigilOptions
var seed_value: int = 0
var layout: SigilCircleLayout
var palette: SigilPalette
var icon_ctx: Dictionary = {}

var live_mode := false
var _time := 0.0
var _tilt := Vector2.ZERO
var _tilt_target := Vector2.ZERO

const PARALLAX_PX := 10.0

var bg: SigilFluidBg
var prism: ColorRect
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

	var s := options.effective_size()
	custom_minimum_size = s
	size = s
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true # <--- ГЛАВНЫЙ ФИКС: ничего не может выйти за карту

	var cr := options.circle_rect()
	layout = SigilCircleLayout.build(seed_value, recipe, cr.get_center(), cr.size.x * 0.5, options)
	icon_ctx = build_icon_ctx(seed_value, recipe, options, palette)

	_ensure_nodes()
	_place_nodes(cr)
	_refresh()
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
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.clip_text = true
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.ellipsis_char = "…"
		title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
		title.add_theme_constant_override("outline_size", 6)
		# Название карточки — «display»-шрифт (Divagon из theme.json), fallback default.
		var disp := get_theme_default_font()
		if has_theme_font("display", "Label"):
			disp = get_theme_font("display", "Label")
		title.add_theme_font_override("font", disp)
		add_child(title)
	if glitch == null:
		glitch = SigilGlitchView.new()
		glitch.name = "Glitch"
		add_child(glitch)

func _layout_full(c: Control, s: Vector2, overscan: float) -> void:
	# Правильный способ для Godot 4: якоря в 0,0 а не FULL_RECT
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.position = Vector2(-overscan, -overscan)
	c.size = s + Vector2(overscan, overscan) * 2.0

func _place_nodes(cr: Rect2) -> void:
	var s := options.effective_size()
	
	# Фоновые слои без оверскана
	for c in [bg, prism, aura, frame, glitch]:
		_layout_full(c as Control, s, 0.0)
	
	# Параллакс-слои делаем заранее больше на PARALLAX_PX, чтобы при сдвиге не было дыр
	for c in [foil, circle, sparkles]:
		_layout_full(c as Control, s, PARALLAX_PX)

	var icon_d := layout.icon_radius * 2.0
	icon.position = layout.icon_center() - Vector2(icon_d, icon_d) * 0.5
	icon.size = Vector2(icon_d, icon_d)
	icon.visible = options.show_icon

	# --- ФИКС НАЗВАНИЯ ---
	title.visible = options.show_name
	title.text = options.name_text if options.name_text != "" else String(recipe.display_name)
	title.add_theme_font_size_override("font_size", options.name_font_size)
	title.add_theme_color_override("font_color", palette.ink)
	
	var band := options.title_rect()
	# Клампим банд строго внутрь карты и внутрь рамки
	band = band.intersection(Rect2(Vector2.ZERO, s).grow(-2.0))
	# Не даем тексту прилипнуть к краю
	band = band.grow(-2.0)
	title.position = band.position
	title.size = band.size
	title.pivot_offset = band.size * 0.5

func _refresh() -> void:
	bg.setup(options, palette, seed_value)
	_setup_prism()
	aura.setup(options, palette, layout.center, layout.radius, seed_value)
	foil.setup(SigilFinishView.Part.FOIL, options, palette, seed_value, layout.icon_center(), layout.radius)
	circle.setup(layout, palette, options)
	sparkles.setup(SigilFinishView.Part.SPARKLES, options, palette, seed_value, layout.icon_center(), layout.radius)
	if options.show_icon:
		icon.setup(SigilGeneratorRegistry.get_generator(recipe.result_type), icon_ctx, SigilRng.new(seed_value).fork("icon"), palette.ink, palette.accent)
	frame.setup(options, palette, seed_value)
	glitch.setup(palette.glitch, seed_value)
	queue_redraw()

func _process(delta: float) -> void:
	if not live_mode: return
	_time += delta
	_tilt = _tilt.lerp(_tilt_target, clampf(delta * 7.0, 0.0, 1.0))
	_apply_parallax()
	if prism != null and prism.visible and prism.material != null:
		(prism.material as ShaderMaterial).set_shader_parameter("phase", Time.get_ticks_msec() / 1000.0)

func set_tilt(normalized: Vector2) -> void:
	_tilt_target = Vector2(clampf(normalized.x, -1.0, 1.0), clampf(normalized.y, -1.0, 1.0))

func play_reveal() -> void:
	if not live_mode: return
	var ordered: Array = []
	for n in [bg, aura, foil, circle, sparkles, frame]:
		var c := n as Control
		if c == null or not c.visible: continue
		ordered.append(c)
	for c in ordered: (c as Control).modulate.a = 0.0
	var tw := create_tween().set_parallel()
	var delay := 0.0
	for c in ordered:
		var node := c as Control
		node.pivot_offset = node.size * 0.5
		node.scale = Vector2(0.90, 0.90)
		tw.tween_property(node, "modulate:a", 1.0, 0.30).set_delay(delay)
		tw.tween_property(node, "scale", Vector2.ONE, 0.42).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		delay += 0.07

func _apply_parallax() -> void:
	var d := PARALLAX_PX
	# База -PARALLAX_PX т.к. слои изначально увеличены
	var base := Vector2(-PARALLAX_PX, -PARALLAX_PX)
	foil.position     = base + _tilt * d * 0.30
	circle.position   = base + _tilt * d * 0.45
	sparkles.position = base + _tilt * d * 0.55

static func build_icon_ctx(seed_value: int, recipe: SigilRecipe, options: SigilOptions, palette: SigilPalette) -> Dictionary:
	var rng := SigilRng.new(seed_value).fork("iconctx")
	var ctx: Dictionary = {"seed": seed_value, "rarity": recipe.rarity, "pixel_grid": options.pixel_grid, "properties": recipe.properties.duplicate(true)}
	for k in recipe.properties.keys(): ctx[str(k)] = recipe.properties[k]
	var ip: Dictionary = {}
	if recipe.properties.has("icon_palette") and typeof(recipe.properties["icon_palette"]) == TYPE_DICTIONARY:
		ip = (recipe.properties["icon_palette"] as Dictionary).duplicate(true)
	else:
		var h := fposmod(palette.aura_color.h + rng.randf_range(-0.12, 0.12), 1.0)
		var body := Color.from_hsv(h, rng.randf_range(0.30, 0.75), rng.randf_range(0.45, 0.88))
		ip = {"body": body, "ink": palette.ink, "accent": palette.accent, "belly": body.lerp(Color(1, 1, 1), 0.5), "deep": body.lerp(Color(0.05, 0.08, 0.16), 0.7), "shallow": body.lerp(Color(0.4, 0.7, 0.9), 0.5), "land": body.lerp(Color(0.35, 0.55, 0.3), 0.55), "high": Color(0.85, 0.88, 0.85), "ice": Color(0.92, 0.96, 1.0), "atmosphere": palette.aura_color.lerp(Color(0.7, 0.85, 1.0), 0.55), "ring": body.lerp(Color(0.9, 0.92, 0.95), 0.5)}
	ctx["icon_palette"] = ip
	return ctx

func set_debug_slots(v: bool) -> void:
	circle.set_debug_slots(v)
	circle.queue_redraw()

func _setup_prism() -> void:
	if prism == null: return
	var eff := String(options.prism_effect).strip_edges()
	if eff == "":
		prism.visible = false; prism.material = null; return
	var sh := load("res://game/sigil/shaders/prism/%s.gdshader" % eff)
	if sh == null: prism.visible = false; prism.material = null; return
	if eff == "galaxy": move_child(prism, 1)
	else: move_child(prism, get_child_count() - 1)
	var ph := options.prism_phase
	if ph < 0.0: ph = float(seed_value % 1000) / 1000.0
	var mat := ShaderMaterial.new()
	mat.shader = sh
	prism.material = mat
	prism.visible = true
	prism.color = Color(1, 1, 1, 1)
	prism.self_modulate.a = 1.0
	mat.set_shader_parameter("phase", ph)
	prism.queue_redraw()

func set_live(v: bool) -> void:
	live_mode = v
	set_process(v)
	if bg != null: bg.set_live(v)