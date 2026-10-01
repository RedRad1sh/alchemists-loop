extends RefCounted
class_name SuiteSigilCards
# Аркан Сигилов: опции рендера, карточка «только круг», каталог и кнопка шапки.


## Мелкий рецепт с зафиксированным сидом: карточка 96×96 рисуется быстро,
## а seed_override снимает зависимость от canonical_string.
static func _recipe(seed_value: int, result_id: String) -> SigilRecipe:
	var r := SigilRecipe.new()
	r.id = StringName("st_" + result_id)
	r.ingredients = PackedStringArray(["fire", "water"])
	r.result_type = &"object"
	r.result_id = StringName(result_id)
	r.rarity = &"common"
	r.display_name = "Пар"
	r.seed_override = seed_value
	return r


static func _small_options() -> Dictionary:
	return {
		"card_size": Vector2(96, 96), "render_scale": 1,
		"show_name": false, "show_frame": false,
		"fluid_enabled": false, "aura_enabled": false, "save_png": false,
	}


static func run(g: Game) -> void:
	# ---- SigilOptions.show_icon ----
	var on := SigilOptions.make({})
	var off := SigilOptions.make({"show_icon": false})
	Selftest.check("options show icon by default", on.show_icon)
	Selftest.check("options hide icon", not off.show_icon)
	Selftest.check("icon flag roundtrips", not SigilOptions.make(off.to_dict()).show_icon)
	Selftest.check("icon flag in dict", off.to_dict().get("show_icon", true) == false)
	Selftest.check("icon flag changes cache salt", on.cache_salt() != off.cache_salt())

	# ---- Карточка «только круг» ----
	var recipe := _recipe(987654321, "steam")
	var full := SigilCard.new()
	g.add_child(full)
	full.setup(recipe, SigilOptions.make(_small_options()))

	var no_icon_opts := _small_options()
	no_icon_opts["show_icon"] = false
	var circle_only := SigilCard.new()
	g.add_child(circle_only)
	circle_only.setup(recipe, SigilOptions.make(no_icon_opts))

	Selftest.check("full card shows icon", full.icon != null and full.icon.visible)
	Selftest.check("circle-only card hides icon", not circle_only.icon.visible)
	Selftest.check("circle-only card keeps circle",
		circle_only.circle != null and circle_only.circle.visible)
	Selftest.check("circle-only card keeps frame slot", circle_only.frame != null)
	Selftest.check("circle-only card keeps same seed", circle_only.seed_value == full.seed_value)

	full.queue_free()
	circle_only.queue_free()

	# ---- Транспорт: новые сигил-запросы существуют и разводят сигналы ----
	Selftest.check("net has catalog request", Net.has_method("sigil_catalog"))
	Selftest.check("net has collection request", Net.has_method("sigil_collection"))
	Selftest.check("net has catalog signal", Net.has_signal("sigil_catalog_result"))
	Selftest.check("net has collection signal", Net.has_signal("sigil_collection_result"))
