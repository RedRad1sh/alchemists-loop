@tool
class_name ProgressLogic extends GraphLogic

@export var block_if_unlocked: bool = true

func get_permission(atom: Atom, graph: Graph, progress: ProgressDB) -> Return:
	if not progress or not atom.data: return Return.PASS

	if block_if_unlocked and progress.is_unlocked(atom.data.id): return Return.BLOCK
	if graph.has_unlocked_neighbor(atom, progress, Graph.ConnectionDir.INBOUND): return Return.ALLOW

	return Return.PASS # Нет родителей? Мы не разрешаем, но и не запрещаем. Вдруг это Root?

func apply_status(atom: Atom, graph: Graph, progress: ProgressDB = null) -> bool:
	var perm = get_permission(atom, graph, progress)
	match perm:
		GraphLogic.Return.BLOCK:
			if atom.status != atom.Status.UNLOCKED: atom.status = atom.Status.UNLOCKED
			return false
		GraphLogic.Return.PASS:
			if atom.status != atom.Status.LOCKED: atom.status = atom.Status.LOCKED
			return true
		GraphLogic.Return.ALLOW:
			if atom.status != atom.Status.AVAILABLE: atom.status = atom.Status.AVAILABLE
			return true
	return false
