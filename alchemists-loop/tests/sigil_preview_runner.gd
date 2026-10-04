extends Node
## Превью 50 сигильных карточек через SigilRenderService (сцена обязательна —
## SubViewport требует живого дерева и кадров). Запуск:
##   Godot --headless --path alchemists-loop --scene res://tests/sigil_preview.tscn
## Вывод: user://sigil_preview/*.png (50 полноразмерных карточек).

var _svc: SigilRenderService
var _recipes: Array = []
var _idx := 0

func _ready() -> void:
	_svc = SigilRenderService.new()
	add_child(_svc)
	var types := ["object", "planet", "creature", "relic", "abstraction"]
	for i in 50:
		var t: String = types[i % types.size()]
		var props := {}
		if t == "object":
			props = {"icon_family": ["machine", "clay", "mineral"][i % 3]}
		elif t == "planet":
			props = {"planet_type": ["terrestrial", "ice", "gas", "molten"][i % 4], "rings": i % 3}
		elif t == "creature":
			props = {"creature_archetype": ["serpent", "avian", "beast"][i % 3]}
		elif t == "relic":
			props = {"form": ["armillary", "phial", "talisman"][i % 3]}
		elif t == "abstraction":
			props = {"form": ["eye", "mandala", "sigil_stack", "transmutation"][i % 4]}
		var r := SigilRecipe.from_dict({
			"id": "preview_%02d" % i,
			"display_name": "Карта %02d" % i,
			"ingredients": ["sulfur", "salt", "water", "fire"].slice(0, 2 + (i % 3)),
			"result_type": t,
			"rarity": ["common", "uncommon", "rare", "epic", "mythic"][i % 5],
			"properties": props,
		})
		_recipes.append(r)
	print("SIGIL-PREVIEW recipes:", _recipes.size())
	_render_next()

func _render_next() -> void:
	if _idx >= _recipes.size():
		print("SIGIL-PREVIEW done: user://sigil_preview/ (", _recipes.size(), ")")
		get_tree().quit(0)
		return
	var r: SigilRecipe = _recipes[_idx]
	_render_one(r)

func _render_one(r: SigilRecipe) -> void:
	var opts := SigilOptions.make()
	opts.card_size = Vector2i(256, 256)
	opts.pixel_grid = 34
	opts.fluid_cpu_fallback = false
	var img: Image = await _svc.render(r, opts)
	var fname := "%s_%s.png" % [String(r.result_type), r.id]
	if not DirAccess.dir_exists_absolute("user://sigil_preview"):
		DirAccess.make_dir_recursive_absolute("user://sigil_preview")
	var ok := img.save_png("user://sigil_preview/" + fname)
	print("preview ", _idx, " ", fname, " ok=", ok)
	_idx += 1
	_render_next()