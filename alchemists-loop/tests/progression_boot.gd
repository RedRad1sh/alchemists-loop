extends Node

var _epoch := 1794614400.0
var _report_path := "res://.godot/progression-final.json"
var _progress_path := "res://.godot/progression-progress.json"
var _game: Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var profile_path := ""
	var seed_value := 1
	var mutation := ""
	var scenario_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="):
			profile_path = arg.trim_prefix("--profile=")
		elif arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--report="):
			_report_path = arg.trim_prefix("--report=")
		elif arg.begins_with("--progress="):
			_progress_path = arg.trim_prefix("--progress=")
		elif arg.begins_with("--mutation="):
			mutation = arg.trim_prefix("--mutation=")
		elif arg.begins_with("--scenario="):
			scenario_path = arg.trim_prefix("--scenario=")
	var initial := {"schema": 1, "verdict": "fail", "state": "fail", "reason": "boot_or_script_failure", "seed": seed_value}
	if not ProgressionReport.write_atomic(_report_path, initial):
		get_tree().quit(2)
		return
	if not OS.get_cmdline_user_args().has("--selftest"):
		_fail("selftest_required")
		return
	var profile := BalanceConfig.load_profile_json(profile_path) if not profile_path.is_empty() else BalanceConfig.baseline()
	if profile == null:
		_fail("invalid_profile")
		return
	var scene: PackedScene = load("res://main.tscn")
	if scene == null:
		_fail("game_scene_load_failed")
		return
	_game = scene.instantiate()
	_game.set_meta("progression_driver", true)
	_game.game_clock = func(): return _epoch
	_game.balance = profile
	_game.SAVE_PATH = "user://progression_engine_save.json"
	_game.TEMP_PATH = "user://progression_engine_save.tmp"
	_game.BACKUP_PATH = "user://progression_engine_save.bak"
	# APPDATA isolation is owned by launcher. Reject reuse instead of reading saves.
	for path in [_game.SAVE_PATH, _game.TEMP_PATH, _game.BACKUP_PATH]:
		if FileAccess.file_exists(path):
			_game.free()
			_fail("run_directory_not_clean")
			return
	add_child(_game)
	await get_tree().process_frame
	_game.set_process(false)
	if not _game._selftest or _game._online._net_enabled:
		_fail("boot_isolation_failed")
		return
	if not mutation.is_empty() and not load("res://tests/progression_mutation_cases.gd").apply(_game, mutation):
		_fail("unknown_mutation")
		return
	if not scenario_path.is_empty():
		seed(seed_value)
		var scenario_clock := ProgressionClock.new(_game)
		scenario_clock.set_virtual_epoch(_epoch)
		var offers := ProgressionSigilFixture.new()
		offers.install(_game)
		var scenario_result := ProgressionScenario.run(_game, _game.balance, seed_value, scenario_path, scenario_clock,
			null, func(status): ProgressionReport.write_atomic(_progress_path, status))
		var stored := ProgressionReport.write_atomic(_report_path, scenario_result)
		_game.game_clock = Callable()
		get_tree().quit(0 if stored and scenario_result.get("verdict") == "pass" else 1)
		return
	var runner := ProgressionRunner.new(_game, seed_value, _game.balance)
	runner.progress_path = _progress_path
	runner.report_path = _report_path
	runner.wall_budget_ms = 300000
	var result := runner.run_phases()
	var saved := ProgressionReport.write_atomic(_report_path, result)
	_game.game_clock = Callable()
	get_tree().quit(0 if saved and result.get("verdict") == "pass" else 1)

func _fail(reason: String) -> void:
	ProgressionReport.write_atomic(_report_path, {"schema": 1, "verdict": "fail", "state": "fail", "reason": reason})
	get_tree().quit(2)
