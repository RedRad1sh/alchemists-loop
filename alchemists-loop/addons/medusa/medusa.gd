@tool
extends EditorPlugin

var addon_path = get_script().get_path().get_base_dir()

func _enter_tree() -> void:
	print_rich("[color=lightgreen]Medusa Framework Enabled[/color]")

func _exit_tree() -> void:
	print_rich("[color=gray]Medusa Framework Disabled[/color]")
