extends RefCounted
class_name WorkshopFixture
# Shared hermetic fixture: snapshots script fields, not UI node ownership.

var g: Game
var snapshots: Array = []
var process_was_on := false
var original_cells: Dictionary = {}
var original_orbs: Dictionary = {}

static func snapshot(game: Game) -> Dictionary:
	return {"fixture": load("res://tests/workshop_fixture.gd").new(game)}

static func restore(_game: Game, state: Dictionary) -> void:
	state["fixture"].finish()

func _init(game: Game) -> void:
	g = game
	original_cells = g._engine._item_cells.duplicate()
	original_orbs = g._engine._item_orbs.duplicate()
	process_was_on = g.is_processing()
	for object in [g, g._engine, g._online, g._pages, g._saves, g._guild,
		g._progress_ui, g._spirit, g._retention, g._resonance, g._retort,
		g._riddles, g._home, g._hub, g._sigil, Net, Analytics, UserData, Sfx]:
		capture(object)
	capture(g.get("_workshop"))
	g.set_process(false)
	g._saves._save_frozen = true
	g._online._net_enabled = false
	Net.set_process(false)
	Net._available = false
	Net.base_url = ""
	Net._queue.clear()
	Net._inflight.clear()
	Analytics._consent = "denied"
	Analytics._configured = false
	g._engine.brewing = false
	g._engine._auto = false
	g._pages._bench_busy = false
	g._engine._experiment_pending_pair.clear()
	g._online._pending_requests.clear()

func capture(object: Object) -> void:
	if object == null:
		return
	var state := {}
	for property in object.get_property_list():
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var key := String(property["name"])
		var value: Variant = object.get(key)
		if value is Object or value is Callable or value is Signal:
			continue
		state[key] = copy_value(value)
	snapshots.append({"object": object, "state": state,
		"processing": object.is_processing() if object is Node else false})

static func copy_value(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value

func finish() -> void:
	for key in g._engine._item_cells:
		if not original_cells.has(key):
			var cell: Node = g._engine._item_cells[key]
			if is_instance_valid(cell):
				if cell.get_parent() != null:
					cell.get_parent().remove_child(cell)
				cell.queue_free()
	for key in g._engine._item_orbs:
		if not original_orbs.has(key) and not g._engine._item_cells.has(key):
			var orb: Node = g._engine._item_orbs[key]
			if is_instance_valid(orb):
				if orb.get_parent() != null:
					orb.get_parent().remove_child(orb)
				orb.queue_free()
	for snapshot in snapshots:
		var object: Object = snapshot["object"]
		for key in snapshot["state"]:
			object.set(key, copy_value(snapshot["state"][key]))
		if object is Node:
			object.set_process(bool(snapshot["processing"]))
	g.set_process(process_was_on)
	snapshots.clear()

func prepare_production() -> void:
	g._engine.inventory = {"fire": 100, "water": 100, "earth": 100, "air": 100}
	g._engine.known_recipes.clear()
	for recipe in g.RECIPES:
		g._engine.known_recipes[g._pair_key(String(recipe["a"]), String(recipe["b"]))] = true
	g._engine.ether = 10000
	g._engine.ether_overflow = 0
	g._engine._craft_job.clear()
	g._engine._blueprints.clear()
	g._engine._rejected_pairs.clear()
	g._engine._layer_cache.clear()
	g._engine._cost_cache.clear()
	g._pages._bench_on = false
	g._engine.spring_on = false
	g.BREW_SECONDS = 0.01
