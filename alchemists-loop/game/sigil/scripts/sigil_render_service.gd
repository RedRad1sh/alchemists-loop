class_name SigilRenderService
extends Node

## Рендер карточки в PNG + кэш на диске.
##
## Узел ОБЯЗАН находиться в дереве сцены — SubViewport рендерит только там.
## Один сервис держит один SubViewport и один [SigilCard] и переиспользует их,
## поэтому поток карточек не порождает мусор в памяти.
##
## Типичный вызов:
##     var svc := SigilRenderService.new()
##     add_child(svc)
##     var path := await svc.export_png(recipe, options)
##
## Кэш: user://sigils/<ключ>.png + <ключ>.json. Ключ = SHA-256 от канонической
## строки рецепта + соль опций + версия формата. Смена версии формата
## инвалидирует старые картинки автоматически.

const CACHE_DIR := "user://sigils"
const FORMAT_VERSION := 4  # 4: исправлена нечитаемая Б/б в шрифте названий
const FRAMES_PER_RENDER := 2

var viewport: SubViewport
var card: SigilCard
var last_key: String = ""


func _ready() -> void:
	if DirAccess.dir_exists_absolute(CACHE_DIR) == false:
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)


# ------------------------------------------------------------------ viewport

func _ensure_viewport(options: SigilOptions) -> void:
	var s := Vector2i(options.effective_size())
	if viewport != null and viewport.size == s and card != null:
		return
	if viewport != null:
		viewport.queue_free()
		viewport = null
	if card != null:
		card.queue_free()
		card = null

	viewport = SubViewport.new()
	viewport.name = "SigilViewport"
	viewport.size = s
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.gui_disable_input = true
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)

	card = SigilCard.new()
	card.name = "Card"
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	viewport.add_child(card)
	card.size = Vector2(s)


# ------------------------------------------------------------------ рендер

## Привязать живой превью-вьюпорт к контейнеру на экране.
## Отдельный путь от экспорта в PNG: картинка перерисовывается сразу,
## файл пишется только по кнопке.
func preview_into(container: SubViewportContainer, options: SigilOptions) -> void:
	if not is_inside_tree():
		push_error("SigilRenderService: добавь сервис в дерево сцены через add_child()")
		return
	_ensure_viewport(options)
	if viewport.get_parent() != container:
		container.add_child(viewport)
	viewport.size = Vector2i(options.effective_size())
	container.stretch = true


func render(recipe: SigilRecipe, options: SigilOptions) -> Image:
	if not is_inside_tree():
		push_error("SigilRenderService: добавь сервис в дерево сцены через add_child()")
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)
	_ensure_viewport(options)
	last_key = recipe.card_key(options.cache_salt() + "|v%d" % FORMAT_VERSION)
	card.setup(recipe, options)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	for i in FRAMES_PER_RENDER:
		await RenderingServer.frame_post_draw
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var img := viewport.get_texture().get_image()
	if img == null:
		push_error("SigilRenderService: не удалось получить изображение из SubViewport")
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)
	return img


# --------------------------------------------------------- центральный элемент

## Центральный объект отдельно от карточки: прозрачный фон, чистый силуэт.
## Тот же рецепт, тот же seed и тот же fork("icon"), что и на круге, поэтому
## пиксель в пиксель совпадает. Без гнезда, ауры, круга, рамки и названия —
## это слои карточки; опору и тень ставит игровой слой, куда иконку вставляют.
##
## side задаёт сторону результата в пикселях; 0 берёт icon_size из опций.
func render_icon(recipe: SigilRecipe, options: SigilOptions, side: int = 0) -> Image:
	if not is_inside_tree():
		push_error("SigilRenderService: добавь сервис в дерево сцены через add_child()")
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)
	var s := side if side > 0 else int(options.icon_size)
	var vp := SubViewport.new()
	vp.name = "IconViewport"
	vp.size = Vector2i(s, s)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.gui_disable_input = true
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(vp)

	var seed_value := recipe.compute_seed()
	var palette := SigilPalette.make(seed_value, recipe.rarity)
	var icon := SigilIconView.new()
	icon.name = "Icon"
	icon.socket = false  # чистый силуэт: гнездо карточки сюда не переносится
	icon.set_anchors_preset(Control.PRESET_TOP_LEFT)
	icon.position = Vector2.ZERO
	icon.size = Vector2(s, s)
	vp.add_child(icon)
	icon.setup(SigilGeneratorRegistry.get_generator(recipe.result_type),
		SigilCard.build_icon_ctx(seed_value, recipe, options, palette),
		SigilRng.new(seed_value).fork("icon"), palette.ink, palette.accent)

	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	for i in FRAMES_PER_RENDER:
		await RenderingServer.frame_post_draw
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null:
		push_error("SigilRenderService: не удалось получить иконку из SubViewport")
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)
	return img


## Выгрузка иконки в PNG. Иконки кэшируются отдельно от карточек:
## у них другой ключ, иначе декора и карточки дрались бы за один файл.
func export_icon_png(recipe: SigilRecipe, options: SigilOptions,
		path: String = "", side: int = 0) -> String:
	var target := path if path != "" else icon_cache_path(recipe, options)
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if path == "" and FileAccess.file_exists(target):
		return target
	var img := await render_icon(recipe, options, side)
	if img.save_png(target) != OK:
		push_error("SigilRenderService: не удалось сохранить иконку в " + target)
		return ""
	return target


func icon_cache_path(recipe: SigilRecipe, options: SigilOptions) -> String:
	return "%s/icon_%s.png" % [CACHE_DIR, icon_cache_key(recipe, options)]


func icon_cache_key(recipe: SigilRecipe, options: SigilOptions) -> String:
	return ("%s_v%d" % [recipe.card_key(options.cache_salt()), FORMAT_VERSION]).sha256_text()


# ------------------------------------------------------------------ кэш

func cache_path(recipe: SigilRecipe, options: SigilOptions) -> String:
	return "%s/%s.png" % [CACHE_DIR, cache_key(recipe, options)]


func cache_key(recipe: SigilRecipe, options: SigilOptions) -> String:
	return ("%s_v%d" % [recipe.card_key(options.cache_salt()), FORMAT_VERSION]).sha256_text()


func has_cached(recipe: SigilRecipe, options: SigilOptions) -> bool:
	return FileAccess.file_exists(cache_path(recipe, options))


func load_cached(recipe: SigilRecipe, options: SigilOptions) -> Image:
	var p := cache_path(recipe, options)
	if not FileAccess.file_exists(p):
		return null
	return Image.load_from_file(p)


func export_png(recipe: SigilRecipe, options: SigilOptions, path: String = "") -> String:
	var target := path if path != "" else cache_path(recipe, options)
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if FileAccess.file_exists(target) and path == "":
		return target
	var img := await render(recipe, options)
	var err := img.save_png(target)
	if err != OK:
		push_error("SigilRenderService: не удалось сохранить %s (err %d)" % [target, err])
		return ""
	if path == "":
		_write_meta(recipe, options, target)
	return target


## Кэш-первый вариант: не перерисовывает, если PNG уже есть.
func export_cached(recipe: SigilRecipe, options: SigilOptions) -> String:
	var p := cache_path(recipe, options)
	if FileAccess.file_exists(p):
		return p
	return await export_png(recipe, options, "")


func _write_meta(recipe: SigilRecipe, options: SigilOptions, png_path: String) -> void:
	var meta := {
		"format_version": FORMAT_VERSION,
		"seed": recipe.compute_seed(),
		"recipe": recipe.to_dict(),
		"options": options.to_dict(),
		"layout_signature": layout_signature(recipe, options),
		"png": png_path.get_file(),
	}
	var f := FileAccess.open(png_path.get_basename() + ".json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(meta, "  "))
		f.close()


func layout_signature(recipe: SigilRecipe, options: SigilOptions) -> String:
	## Отпечаток круга БЕЗ отрисовки. Дешёвый способ проверить детерминизм
	## и сравнить круг с сохранённой картинкой, не читая PNG.
	var cr := options.circle_rect()
	var l := SigilCircleLayout.build(recipe.compute_seed(), recipe, cr.get_center(),
		cr.size.x * 0.5, options)
	return l.signature()


# ------------------------------------------------------------------ контактный лист

func contact_sheet(recipes: Array, options: SigilOptions, columns: int = 6,
		path: String = "") -> String:
	## Сетка карточек одним PNG — быстрый способ оценить семейство рецептов.
	var cols := maxi(columns, 1)
	var rows := int(ceil(float(recipes.size()) / float(cols)))
	var cell := options.effective_size()
	var pad := 8
	var sheet := Image.create(int(cell.x * cols) + pad * (cols + 1),
		int(cell.y * rows) + pad * (rows + 1), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.05, 0.05, 0.07, 1.0))
	for i in recipes.size():
		var r: SigilRecipe = recipes[i]
		var img := await render(r, options)
		if img == null:
			continue
		var cx := i % cols
		var cy := i / cols
		var at := Vector2i(pad + cx * (int(cell.x) + pad), pad + cy * (int(cell.y) + pad))
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
	var out := path if path != "" else "%s/_contact_sheet.png" % CACHE_DIR
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	sheet.save_png(out)
	return out


func clear_cache() -> int:
	var n := 0
	var d := DirAccess.open(CACHE_DIR)
	if d == null:
		return 0
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir() and f.ends_with(".png"):
			d.remove(f)
			n += 1
		f = d.get_next()
	d.list_dir_end()
	return n
