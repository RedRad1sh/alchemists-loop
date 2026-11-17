extends Control

const RESOURCES := [
	"res://assets/ui/room/room_plate.png",
	"res://assets/ui/room/workshop_plate.png",
	"res://assets/ui/room/prop_retort.png",
	"res://assets/ui/room/prop_spring.png",
	"res://assets/ui/room/prop_bench.png",
	"res://assets/fonts/Manrope-Regular.ttf",
	"res://main.tscn",
]
var _loaded: Array[Resource] = []
var _progress: ProgressBar
var _status: Label
var _retry: Button

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("191510")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 310
	content.add_theme_constant_override("separation", 24)
	center.add_child(content)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/ui/icons/frame_crest.svg")
	logo.custom_minimum_size = Vector2(280, 80)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.modulate = Color("e6b87a")
	content.add_child(logo)
	var title := Label.new()
	title.text = "ПЕТЛЯ АЛХИМИКА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", load("res://assets/fonts/Alchemist-Runic.ttf"))
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color("efe0bd"))
	content.add_child(title)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size.y = 5
	_progress.show_percentage = false
	_progress.max_value = 1.0
	var track := StyleBoxFlat.new()
	track.bg_color = Color("382e23")
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("c9ad7e")
	_progress.add_theme_stylebox_override("background", track)
	_progress.add_theme_stylebox_override("fill", fill)
	content.add_child(_progress)
	_status = Label.new()
	_status.text = "Загрузка…"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color("a98d74"))
	content.add_child(_status)
	_retry = Button.new()
	_retry.text = "Повторить"
	_retry.hide()
	_retry.pressed.connect(_load_game)
	content.add_child(_retry)
	_load_game()

func _load_game() -> void:
	_retry.hide()
	_loaded.clear()
	_progress.value = 0.0
	_status.text = "Загрузка…"
	await get_tree().process_frame
	for i in RESOURCES.size():
		var path: String = RESOURCES[i]
		var error := ResourceLoader.load_threaded_request(path)
		if error != OK:
			_failed(path)
			return
		var progress: Array = []
		var state := ResourceLoader.load_threaded_get_status(path, progress)
		while state == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_progress.value = (float(i) + float(progress[0])) / float(RESOURCES.size() + 1)
			await get_tree().process_frame
			state = ResourceLoader.load_threaded_get_status(path, progress)
		if state != ResourceLoader.THREAD_LOAD_LOADED:
			_failed(path)
			return
		_loaded.append(ResourceLoader.load_threaded_get(path))
		_progress.value = float(i + 1) / float(RESOURCES.size() + 1)
	_status.text = "Подготовка мастерской…"
	await get_tree().process_frame
	var scene := _loaded.back() as PackedScene
	var game := scene.instantiate()
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	_progress.value = 1.0
	queue_free()

func _failed(path: String) -> void:
	_status.text = "Не удалось загрузить ресурсы."
	_status.tooltip_text = path
	_retry.show()
