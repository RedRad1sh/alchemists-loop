extends Node
## Анимационное превью Prism-эффектов: N кадров на эффект (phase 0..1).
## Запуск (GUI): Godot --path alchemists-loop --scene res://tests/prism_gif.tscn
## Вывод: user://sigil_preview/prism_gif/<eff>/frame_XX.png
## Сборка в GIF — Python (PIL) после прогона.

const FRAMES := 10

var _svc: SigilRenderService
var _effects: Array = ["galaxy", "oil_slick", "textured_foil",
	"shattered_glass", "laser_refraction", "glitch"]
var _eff_idx := 0
var _frame_idx := 0

func _ready() -> void:
	_svc = SigilRenderService.new()
	add_child(_svc)
	_render_next()

func _render_next() -> void:
	if _eff_idx >= _effects.size():
		print("PRISM-GIF done: user://sigil_preview/prism_gif/")
		get_tree().quit(0)
		return
	var eff: String = String(_effects[_eff_idx])
	var r := SigilRecipe.from_dict({
		"id": "prism_demo",
		"display_name": "Prism " + eff,
		"ingredients": ["sulfur", "salt", "water", "fire"],
		"result_type": "relic",
		"rarity": "epic",
		"properties": {"form": "armillary"},
	})
	var phase := float(_frame_idx) / float(FRAMES - 1)
	var opts := SigilOptions.make({
		"card_size": Vector2i(384, 512),
		"prism_effect": eff,
		"prism_phase": phase,
	})
	_render_one(r, opts, eff)

func _render_one(r: SigilRecipe, opts: SigilOptions, eff: String) -> void:
	# НОВЫЙ сервис на кадр: переиспользование SubViewport с UPDATE_DISABLED
	# кэширует первый рендер и игнорирует смену phase (кадры идентичны).
	var svc := SigilRenderService.new()
	add_child(svc)
	var img: Image = await svc.render(r, opts)
	svc.queue_free()
	var dir := "user://sigil_preview/prism_gif/%s" % eff
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var fname := "frame_%02d.png" % _frame_idx
	var ok := img.save_png("%s/%s" % [dir, fname])
	print("gif ", eff, " frame ", _frame_idx, " ok=", ok)
	_frame_idx += 1
	if _frame_idx >= FRAMES:
		_frame_idx = 0
		_eff_idx += 1
	_render_next()