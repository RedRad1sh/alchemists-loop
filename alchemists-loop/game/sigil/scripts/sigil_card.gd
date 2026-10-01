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

var bg: SigilFluidBg
var aura: SigilAuraView
var circle: SigilCircleView
var icon: SigilIconView
var frame: SigilFrameView
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
	setup_done.emit(self)


func _ensure_nodes() -> void:
	if bg == null:
		bg = SigilFluidBg.new()
		bg.name = "FluidArt"
		add_child(bg)
	if aura == null:
		aura = SigilAuraView.new()
		aura.name = "Aura"
		add_child(aura)
	if circle == null:
		circle = SigilCircleView.new()
		circle.name = "Circle"
		add_child(circle)
	if icon == null:
		icon = SigilIconView.new()
		icon.name = "Icon"
		add_child(icon)
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


func _place_nodes(cr: Rect2) -> void:
	var s := options.effective_size()
	for c in [bg, aura, circle, frame]:
		(c as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
		(c as Control).position = Vector2.ZERO
		(c as Control).size = s

	var icon_d := layout.icon_radius * 2.0
	icon.position = layout.icon_center() - Vector2(icon_d, icon_d) * 0.5
	icon.size = Vector2(icon_d, icon_d)

	icon.visible = options.show_icon
	title.visible = options.show_name
	title.text = options.name_text if options.name_text != "" else String(recipe.display_name)
	title.add_theme_font_size_override("font_size", options.name_font_size)
	title.add_theme_color_override("font_color", palette.ink)
	var tr := options.title_rect()
	title.position = tr.position
	title.size = tr.size


func _refresh() -> void:
	bg.setup(options, palette, seed_value)
	aura.setup(options, palette, layout.center, layout.radius, seed_value)
	circle.setup(layout, palette, options)
	if options.show_icon:
		icon.setup(SigilGeneratorRegistry.get_generator(recipe.result_type), icon_ctx,
			SigilRng.new(seed_value).fork("icon"), palette.ink, palette.accent)
	frame.setup(options, palette, seed_value)
	queue_redraw()


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
