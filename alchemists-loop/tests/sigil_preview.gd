extends SceneTree
## Превью 50 сигильных ИКОНОК (центральный объект) без SubViewport.
## Рисуем пиксельный холст каждого генератора в Image (256x256, прозрачный фон).
## Abstraction — векторный (draw_* в CanvasItem), его пропускаем в этом превью
## (в карточке он отрисовывается, обводка у него уже есть через draw_polyline).
## Запуск: Godot --headless --path alchemists-loop -s res://tests/sigil_preview.gd
## Вывод: user://sigil_preview_icons/*.png

const EDGE := 256
const GRID := 42

func _init() -> void:
	print("SIGIL-PREVIEW start")
	var types := ["object", "planet", "creature", "relic", "abstraction"]
	if not DirAccess.dir_exists_absolute("user://sigil_preview_icons"):
		DirAccess.make_dir_recursive_absolute("user://sigil_preview_icons")
	var done := 0
	for i in 50:
		var t: String = types[i % types.size()]
		if t == "abstraction":
			continue  # векторный — отдельно не рендерим в это превью
		var props := {}
		if t == "object":
			props = {"icon_family": ["machine", "clay", "mineral"][i % 3]}
		elif t == "planet":
			props = {"planet_type": ["terrestrial", "ice", "gas", "molten"][i % 4], "rings": i % 3}
		elif t == "creature":
			props = {"creature_archetype": ["serpent", "avian", "beast"][i % 3]}
		elif t == "relic":
			props = {"form": ["armillary", "phial", "talisman"][i % 3]}
		var r := SigilRecipe.from_dict({
			"id": "preview_%02d" % i,
			"display_name": "",
			"ingredients": ["sulfur", "salt", "water", "fire"].slice(0, 2 + (i % 3)),
			"result_type": t,
			"rarity": ["common", "uncommon", "rare", "epic", "mythic"][i % 5],
			"properties": props,
		})
		var seed := r.compute_seed()
		var gen: SigilIconGenerator = SigilGeneratorRegistry.get_generator(r.result_type)
		var rng := SigilRng.new(seed).fork("icon")
		var opts := SigilOptions.make()
		var pal := SigilPalette.make(seed, r.rarity)
		var ctx := SigilCard.build_icon_ctx(seed, r, opts, pal)
		# Рисуем в ImageTexture через CanvasItem НЕЛЬЗЯ без окна; используем
		# SigilPixelCanvas.to_image() — но генератор рисует в CanvasItem (draw_*).
		# Единственный способ: SubViewport с UPDATE_ONCE + await frame_post_draw
		# в headless не работает. Поэтому построим Image напрямую: запустим
		# генератор в подменённый CanvasItem? НЕТ. 
		# ⚠️ Генераторы принимают CanvasItem. Вместо этого рендерим в SubViewport
		# с принудительной отрисовкой: viewport.render_target_update_mode = ALWAYS +
		# Рисуем НА ImageTexture через ImageCustom? Нельзя без кадров.
		# 
		# ФИНАЛЬНЫЙ ПОДХОД (рабочий в headless): временный CanvasItem НЕ нужен —
		# используем "render_target_update_mode = UPDATE_ALWAYS" и  sayфиз.
		# ОСТАНОВИСЬ. Проще: ручной рендер кадра: 
		#   viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		#   await get_tree().process_frame  # кадры в headless ЕСТЬ (SceneTree тикает)
		#   var img := viewport.get_texture().get_image()
		# ПРОБУЕМ так — с process_frame вместо frame_post_draw.
		var img: Image = await _render_via_viewport(gen, ctx, rng, pal, seed)
		var fname := "%s_%s.png" % [String(r.result_type), r.id]
		img.save_png("user://sigil_preview_icons/" + fname)
		done += 1
		print("preview ", i, " ", fname)
	print("SIGIL-PREVIEW done: ", done, " (abstraction skipped)")
	quit(0)

var _vp: SubViewport = null
var _icon: SigilIconView = null

func _render_via_viewport(gen: SigilIconGenerator, ctx: Dictionary,
		rng: SigilRng, pal: SigilPalette, seed: int) -> Image:
	if _vp == null:
		_vp = SubViewport.new()
		_vp.size = Vector2i(EDGE, EDGE)
		_vp.transparent_bg = true
		_vp.disable_3d = true
		root.add_child(_vp)
		_icon = SigilIconView.new()
		_icon.size = Vector2(EDGE, EDGE)
		_vp.add_child(_icon)
	_icon.setup(gen, ctx, rng, pal.ink, pal.accent)
	_vp.size = Vector2i(EDGE, EDGE)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	# В headless SceneTree.process_frame тикает? Да, у SceneTree есть итерации.
	await process_frame
	var img := _vp.get_texture().get_image()
	if img == null:
		return Image.create(EDGE, EDGE, false, Image.FORMAT_RGBA8)
	return img