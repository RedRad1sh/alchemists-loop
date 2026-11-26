extends Node
## Кадры приёмки Светика (оп C): маскот под правыми кнопками и только на Столе,
## гаснет под оверлеями. Запуск (ОКНО, не --headless):
##   "$GODOT" --path . --scene res://tests/spirit_shots.tscn
## Вывод: user://spirit_shots/spirit_*.png (4 кадра), затем get_tree().quit.
## Прогон герметичен: сейв подменён на shot-пути до _ready, запись заморожена.

var _game: Game


func _ready() -> void:
	Juice.enabled = true
	# Телефонный масштаб s=1.5: именно на нём фиксированный offset_top=100 ложился
	# на HouseEntry. В headless окно квадратнее и баг не воспроизводится.
	get_window().size = Vector2i(540, 960)
	_game = load("res://main.tscn").instantiate() as Game
	if _game == null:
		push_error("SPIRIT-SHOTS: main.tscn не инстанцируется в Game")
		get_tree().quit(1)
		return
	_game.SAVE_PATH = "user://alchemy_shot_save.json"
	_game.TEMP_PATH = "user://alchemy_shot_save.tmp"
	_game.BACKUP_PATH = "user://alchemy_shot_save.bak"
	add_child(_game)
	_game._saves._save_frozen = true
	for i in 4:
		await get_tree().process_frame
	if _game._shop != null and _game._shop.has_method("_close_consent"):
		_game._shop._close_consent()
		await get_tree().create_timer(0.3).timeout
	if _game._saves != null and _game._saves.has_method("_close_return_popup"):
		_game._saves._close_return_popup()
		await get_tree().create_timer(0.3).timeout
	# Разблокируем маскот без онбординг-диалога и без записи в сейв.
	_game._spirit._companion_unlocked = true
	_game._spirit._companion_met = true
	_game._spirit._player_name = "Алхимик"
	_game._spirit._companion_apply_level()
	await _shot_lab()
	await _shot_world()
	await _shot_friends()
	await _shot_house()
	print("SPIRIT-SHOTS done")
	get_tree().quit(0)


func _diag(tag: String) -> void:
	var c := _game._spirit._companion as Control
	var house := _game._hud.sides.find_child("HouseEntry", true, false) as Control
	var shop := _game._hud.sides.find_child("ShopBtn", true, false) as Control
	print("SPIRIT-DIAG ", tag, " size=", _game.size,
		" vis=", c.visible, " companion=", c.get_global_rect(),
		" house=", (house.get_global_rect() if house != null else Rect2()),
		" shop=", (shop.get_global_rect() if shop != null else Rect2()))


func _shot_lab() -> void:
	_game._tabs_ref.current_tab = Game.TAB_EXPERIMENT
	_game._spirit._refresh_companion_visible()
	for i in 3:
		await get_tree().process_frame
	_diag("lab")
	await _capture("spirit_lab.png")


func _shot_world() -> void:
	_game._tabs_ref.current_tab = Game.TAB_WORLD
	for i in 3:
		await get_tree().process_frame
	_diag("world")
	await _capture("spirit_world.png")


func _shot_friends() -> void:
	_game._tabs_ref.current_tab = Game.TAB_EXPERIMENT
	for i in 2:
		await get_tree().process_frame
	_game._social._seed_demo()
	_game._social_ui.open(0)
	for i in 3:
		await get_tree().process_frame
	_diag("friends")
	await _capture("spirit_friends.png")
	_game._social_ui.close()
	for i in 2:
		await get_tree().process_frame


func _shot_house() -> void:
	_game._tabs_ref.current_tab = Game.TAB_EXPERIMENT
	_game._spirit._refresh_companion_visible()
	for i in 2:
		await get_tree().process_frame
	_game._home._open_workshop()
	for i in 6:
		await get_tree().process_frame
	_diag("house")
	await _capture("spirit_house.png")
	_game._home._close_house_screen()
	for i in 2:
		await get_tree().process_frame


func _capture(fname: String) -> void:
	if not DirAccess.dir_exists_absolute("user://spirit_shots"):
		DirAccess.make_dir_recursive_absolute("user://spirit_shots")
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "user://spirit_shots/" + fname
	print("SPIRIT-SHOT ", path, " ok=", img.save_png(path))