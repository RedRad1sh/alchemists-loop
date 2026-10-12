extends SceneTree
# --script must not preload Game: autoload globals are registered after init.
func _initialize() -> void:
	call_deferred("_boot")

func _boot() -> void:
	if not OS.get_cmdline_user_args().has("--selftest"):
		push_error("WORKSHOP_BOOTSTRAP_REQUIRES -- --selftest")
		quit(2)
		return
	if not OS.get_environment("APPDATA").to_lower().contains("idle-workshop"):
		push_error("WORKSHOP_BOOTSTRAP_REQUIRES isolated idle-workshop APPDATA")
		quit(2)
		return
	var net := root.get_node("Net")
	net.set_process(false)
	net.set("base_url", "")
	net.set("_available", false)
	var script: Script = load("res://tests/workshop_acceptance.gd")
	if script == null or not script.can_instantiate():
		quit(2)
		return
	var game: Control = script.new()
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(game)
