extends Node
## Превью Prism-эффектов (card_beatify): одна карточка × каждый из 6 эффектов
## + контроль без эффекта. Запуск:
##   Godot --path alchemists-loop --scene res://tests/sigil_preview.tscn -- --prism
## Вывод: user://sigil_preview/prism/*.png
## (GUI-запуск обязателен: SubViewport требует живых кадров.)

var _svc: SigilRenderService
var _effects: Array = ["", "galaxy", "oil_slick", "textured_foil",
	"shattered_glass", "laser_refraction", "glitch"]
var _idx := 0

func _ready() -> void:
	_svc = SigilRenderService.new()
	add_child(_svc)
	_render_next()

func _render_next() -> void:
	if _idx >= _effects.size():
		print("PRISM-PREVIEW done: user://sigil_preview/prism/ (", _effects.size(), ")")
		get_tree().quit(0)
		return
	var eff: String = String(_effects[_idx])
	var r := SigilRecipe.from_dict({
		"id": "prism_demo",
		"display_name": "Prism " + (eff if eff != "" else "none"),
		"ingredients": ["sulfur", "salt", "water", "fire"],
		"result_type": "relic",
		"rarity": "epic",
		"properties": {"form": "armillary"},
	})
	var opts := SigilOptions.make({
		"card_size": Vector2i(384, 512),
		"prism_effect": eff,
	})
	_render_one(r, opts, eff)

func _render_one(r: SigilRecipe, opts: SigilOptions, eff: String) -> void:
	var img: Image = await _svc.render(r, opts)
	var dir := "user://sigil_preview/prism"
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var fname := "%s.png" % (eff if eff != "" else "none")
	var ok := img.save_png("%s/%s" % [dir, fname])
	print("prism ", eff, " -> ", fname, " ok=", ok)
	_idx += 1
	_render_next()