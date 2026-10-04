@tool
class_name GraphLogic extends Resource

enum Return {
	BLOCK,  ## Жесткий запрет. Немедленно прерывает цепочку и запрещает покупку.
	PASS,   ## Нейтрально. Логика не имеет возражений, но и не дает права на покупку.
	ALLOW   ## Разрешение. Если никто не кинул DENY, то атом будет разблокирован.
}

func get_permission(atom: Atom, graph: Graph, progress: ProgressDB) -> Return:
	return Return.PASS

## STATUS CONTROL (Called at startup and each time progress is updated in sync_with_progress)
## Here, the logic can change atom.is_disabled, atom.is_hidden, etc.
## Calls the permission to continue the state change cycle.
func apply_status(atom: Atom, graph: Graph, progress: ProgressDB = null) -> bool:
	return false
