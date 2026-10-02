@tool
class_name TagLogic extends GraphLogic

@export var tags: Array[StringName] = [&"root"]
@export var status: Atom.Status = Atom.Status.AVAILABLE

func get_permission(atom: Atom, graph: Graph, progress: ProgressDB) -> Return:
	for t in tags: if t in atom.get_all_tags(): return Return.ALLOW
	return Return.PASS # Если тегов нет - мне всё равно, проверяйте дальше

func apply_status(atom: Atom, graph: Graph, progress: ProgressDB = null) -> bool:
	var perm = get_permission(atom, graph, progress)
	if perm == GraphLogic.Return.ALLOW:
		if atom.status != status: atom.status = status
	return true
