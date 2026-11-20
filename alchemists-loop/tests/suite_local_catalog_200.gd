extends RefCounted
class_name SuiteLocalCatalog200


static func run(g: Game) -> void:
	var server_ids: Dictionary = {}
	for k in g._online._server_elements:
		server_ids[str(k)] = true

	var local_ids: Array[String] = []
	for raw_id in g.ITEMS:
		var sid := str(raw_id)
		if not server_ids.has(sid):
			local_ids.append(sid)

	print("[catalog200] current local ITEMS=%d, RECIPES=%d" % [local_ids.size(), g.RECIPES.size()])

	Selftest.check("catalog200: exact 200 local items", local_ids.size() == 200)

	# Display fields & category coverage
	var fields_ok := true
	var cats_ok := true
	var allowed_cats := {"огонь": true, "вода": true, "воздух": true, "земля": true}
	for sid in local_ids:
		var info: Dictionary = g.ITEMS[sid]
		if String(info.get("name", "")).is_empty() \
				or String(info.get("color", "")).is_empty() \
				or String(info.get("d", "")).is_empty():
			fields_ok = false
		var cat := String(Modes.CATEGORY_OF.get(sid, ""))
		if not allowed_cats.has(cat):
			cats_ok = false
	Selftest.check("catalog200: every local item has name, color and description", fields_ok)
	Selftest.check("catalog200: every local item has an explicit valid Modes.CATEGORY_OF entry", cats_ok)

	# Recipe outputs exist, no server slugs, no mirror duplicate pairs
	var pair_seen: Dictionary = {}
	var pairs_unique := true
	var refs_local := true
	var local_set: Dictionary = {}
	for sid in local_ids:
		local_set[sid] = true
	for r in g.RECIPES:
		var a := String(r.get("a", ""))
		var b := String(r.get("b", ""))
		var out := String(r.get("out", ""))
		if not local_set.has(a) or not local_set.has(b) or not local_set.has(out):
			refs_local = false
		var pk := (a + "|" + b) if a <= b else (b + "|" + a)
		if pair_seen.has(pk):
			pairs_unique = false
		pair_seen[pk] = out
	Selftest.check("catalog200: all recipe inputs and outputs belong to local ITEMS", refs_local)
	Selftest.check("catalog200: no duplicate or mirror-duplicate recipe pairs", pairs_unique)

	# Reachability & acyclic layer computation from the 4 bases
	var layer: Dictionary = {}
	for base_id in Modes.BASE_IDS:
		layer[str(base_id)] = 0
	var changed := true
	while changed:
		changed = false
		for r in g.RECIPES:
			var a := String(r.get("a", ""))
			var b := String(r.get("b", ""))
			var out := String(r.get("out", ""))
			if layer.has(a) and layer.has(b):
				var cand: int = maxi(int(layer[a]), int(layer[b])) + 1
				if not layer.has(out) or cand < int(layer[out]):
					layer[out] = cand
					changed = true
	Selftest.check("catalog200: all 200 local items reachable from the 4 base elements",
		layer.size() == 200 and local_ids.size() == 200)

	# Every non-base local item has at least one monotonic recipe (inputs strictly shallower)
	var monotonic_ok := true
	for sid in local_ids:
		if Modes.BASE_IDS.has(sid):
			continue
		if not layer.has(sid):
			monotonic_ok = false
			continue
		var has_forming := false
		for r in g.RECIPES:
			if String(r.get("out", "")) != sid:
				continue
			var a := String(r.get("a", ""))
			var b := String(r.get("b", ""))
			if layer.has(a) and layer.has(b) and int(layer[a]) < int(layer[sid]) and int(layer[b]) < int(layer[sid]):
				has_forming = true
				break
		if not has_forming:
			monotonic_ok = false
	Selftest.check("catalog200: every non-base local item has an acyclic forming recipe", monotonic_ok)

	# Retort element mapping covers all local items with one of the 4 elements
	var elem_ok := true
	var valid_elems := {"fire": true, "water": true, "earth": true, "air": true}
	for sid in local_ids:
		if not valid_elems.has(RetortBalance.element_of(sid)):
			elem_ok = false
	Selftest.check("catalog200: RetortBalance.element_of resolves every local item", elem_ok)
