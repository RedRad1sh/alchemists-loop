extends RefCounted
class_name ProgressionDiscoveryFixture

var game: Game
var _catalog: Dictionary = {}
var _recipes: Dictionary = {}
var _requests: Array = []


func install(target_game: Game, local_catalog: Dictionary, recipes: Array) -> void:
	game = target_game
	_catalog = local_catalog.duplicate(true)
	_recipes.clear()
	for raw in recipes:
		var recipe: Dictionary = raw
		_recipes[game._pair_key(String(recipe.get("a", "")), String(recipe.get("b", "")))] = String(recipe.get("out", ""))
	_requests.clear()
	game._online.set_discovery_transport(_on_request)


func uninstall() -> void:
	if game != null:
		game._online.clear_discovery_transport()
	game = null
	_requests.clear()


func _on_request(a: String, b: String, experiment: bool) -> void:
	_requests.append({"a": a, "b": b, "experiment": experiment, "key": game._pair_key(a, b)})


func respond_success(pair_key: String, output: String = "") -> void:
	if game == null:
		return
	var entry := _take(pair_key)
	if entry.is_empty():
		return
	var slug := output
	if slug.is_empty():
		slug = String(_recipes.get(pair_key, ""))
	if slug.is_empty():
		slug = "fixture_success"
	var info: Dictionary = _catalog.get(slug, {
		"name": "Fixture Success", "color": "#8899aa", "g": "fire",
		"d": "Deterministic fixture result.", "category": "огонь"})
	var result := {"ok": true, "found": true, "out": {
		"slug": slug, "name": String(info.get("name", slug)),
		"color": String(info.get("color", "#8899aa")),
		"glyph": String(info.get("g", "fire")),
		"category": String(info.get("category", "огонь")),
		"d": String(info.get("d", "Deterministic fixture result.")),
		"layer": 1}}
	game._online._on_net_pair_result(pair_key, result)


func respond_refusal(pair_key: String, reason: String = "not_combinable") -> void:
	if game == null:
		return
	if _take(pair_key).is_empty():
		return
	game._online._on_net_pair_result(pair_key, {"ok": false, "status": reason})


func respond_stale(pair_key: String) -> void:
	if game == null:
		return
	game._online._on_net_pair_result(pair_key, {"ok": true, "found": true, "out": {
		"slug": "fixture_stale", "name": "Stale", "color": "#8899aa", "glyph": "fire",
		"category": "огонь", "d": "Stale response.", "layer": 1}})


func requests() -> Array:
	return _requests.duplicate(true)


func _take(pair_key: String) -> Dictionary:
	for i in range(_requests.size() - 1, -1, -1):
		if String(_requests[i].get("key", "")) == pair_key:
			var entry: Dictionary = _requests[i]
			_requests.remove_at(i)
			return entry
	return {}
