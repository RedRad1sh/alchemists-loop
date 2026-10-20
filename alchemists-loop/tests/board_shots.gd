extends Node
## Кадры juice доски: hover-подъём, фазы штамповки, раскрытие награды.
## Запуск (ОКНО, не --headless):
##   "$GODOT" --path . --scene res://tests/board_shots.tscn
## Вывод: user://juice_shots/board_*.png (7 кадров), затем get_tree().quit.

var _game: Game
var _board: ContractBoard
var _card: ContractCard


func _ready() -> void:
	Juice.enabled = true
	_game = load("res://main.tscn").instantiate() as Game
	if _game == null:
		push_error("BOARD-SHOTS: main.tscn не инстанцируется в Game")
		get_tree().quit(1)
		return
	add_child(_game)
	for i in 3:
		await get_tree().process_frame
	if _game._shop != null and _game._shop.has_method("_close_consent"):
		_game._shop._close_consent()
		await get_tree().create_timer(0.3).timeout
	_game._contracts._inject_board_demo()
	ContractBoard.open(_game)
	for i in 2:
		await get_tree().process_frame
	_board = _game.get_node("ContractBoard") as ContractBoard
	_card = null
	for c in _board._cards:
		var card := c as ContractCard
		if card != null and card._stamp.visible and not card._stamp.disabled:
			_card = card
			break
	if _card == null:
		push_error("BOARD-SHOTS: нет карточки с живым штампом")
		get_tree().quit(1)
		return
	await _shot_hover()
	await _shot_seal()
	await _shot_reward()
	print("BOARD-SHOTS done")
	get_tree().quit(0)


func _shot_hover() -> void:
	_card._set_hover(true)
	await get_tree().create_timer(0.06).timeout
	await _capture("board_hover_mid.png")
	await get_tree().create_timer(0.10).timeout
	await _capture("board_hover_up.png")
	_card._set_hover(false)
	await get_tree().create_timer(0.15).timeout


func _shot_seal() -> void:
	_card._seal_slam()
	await _capture("board_seal_00.png")
	await get_tree().create_timer(0.09).timeout
	await _capture("board_seal_09.png")
	await get_tree().create_timer(0.09).timeout
	await _capture("board_seal_18.png")
	await get_tree().create_timer(0.30).timeout


func _shot_reward() -> void:
	_card._on_stamp_pressed()
	await get_tree().create_timer(0.30).timeout
	await _capture("board_reward_open.png")
	await get_tree().create_timer(0.25).timeout
	await _capture("board_reward_settled.png")


func _capture(fname: String) -> void:
	if not DirAccess.dir_exists_absolute("user://juice_shots"):
		DirAccess.make_dir_recursive_absolute("user://juice_shots")
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "user://juice_shots/" + fname
	print("BOARD-SHOT ", path, " ok=", img.save_png(path))
