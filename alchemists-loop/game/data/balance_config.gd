extends RefCounted
class_name BalanceConfig

const SCHEMA_VERSION := 1

const BASELINE_DATA := {
	"ether": {
		"brew_cost": 12,
		"failure_refund": 2,
		"base_regen": 0.35,
		"regen_per_upgrade": 0.35,
		"cap_per_upgrade": 50,
		"max_ether": 180,
		"start_ether": 100,
		"mastery_base": 300,
		"mastery_growth": 1.35,
		"hint_cost": 10,
		"spend_guard_msec": 250,
	},
	"brew": {
		"base_seconds": 1.2,
		"minimum_seconds": 0.35,
		"speed_factor": 0.90,
		"blueprint_discount": 0.90,
		"guild_all_bonus": 100,
	},
	"discovery": {
		"fees": {1: 4, 2: 6, 3: 10, 4: 16, 5: 24, 6: 36},
		"bounties": [0, 6, 12, 25, 45],
		"arity_min": 2,
		"arity_max": 2,
		"cooldown_sec": 1.0,
		"daily_limit": 200,
		"cost": 12,
		"candidate_chance": 0.05,
		"candidate_cooldown": 60.0,
	},
	"personal_experiment": {
		"enabled": true,
		"cost": 12,
		"success_only_ether": true,
		"consume_reagents": false,
		"world_target_share": 0.8,
		"llm_target_share": 0.2,
		"frontier_empty_llm_share": 1.0,
	},
	"upgrades": {
		"items": [
			{"id": "ether_regen", "name": "Поток эфира", "desc": "+0.35 эфира в секунду",
				"base": 150, "growth": 1.55, "max": 4, "unlock": "steam"},
			{"id": "ether_cap", "name": "Ёмкость эфира", "desc": "+50 к максимуму эфира",
				"base": 70, "growth": 1.32, "max": 8, "unlock": "clay"},
			{"id": "brew_speed", "name": "Скороварка", "desc": "каждая варка на 10% быстрее",
				"base": 170, "growth": 1.5, "max": 4, "unlock": "glass"},
			{"id": "source_yield", "name": "Щедрые источники", "desc": "каждая 8/7/6/5-я добыча даёт +1 сверху",
				"base": 220, "growth": 1.6, "max": 3, "unlock": "mushroom"},
			{"id": "auto_gift", "name": "Дары", "desc": "случайное открытое вещество +1 каждые 2 минуты",
				"base": 450, "growth": 1.0, "max": 1, "unlock": "fish"},
		],
	},
	"offline": {
		"min_sec": 60.0,
		"cap_sec": 12 * 3600.0,
		"return_gap_sec": 1800.0,
	},
	"events": {
		"bench_interval": 40.0,
		"bench_offline_factor": 0.5,
		"bench_offline_max_ticks": 60,
		"gift_interval": 120.0,
		"event_interval": 150.0,
		"event_window": 8.0,
		"challenge_reward": 50,
	},
	"sync": {
		"schema_version": 4,
		"max_accrual_rate_per_sec": 1000.0,
		"throttle_sec": 60.0,
	},
	"caps": {
		"craft_inventory_stack_cap": 1000000,
		"craft_stage_operations": 3,
		"craft_plan_warning_operations": 20,
		"craft_plan_hard_limit_operations": 200,
		"world_page_size": 25,
		"net_nick": "Алхимик",
	},
	"mastery": {
		"stage_ranks": [3, 7],
		"retort_speed": 0.06,
		"retort_min_hours": 6.0,
	},
	"prestige": {
		"regen_per_gold": 0.04,
		"regen_gold_cap": 15,
		"cap_per_gold": 40,
		"min_items": 30,
		"spring_keep_level": 3,
	},
	"milestones": {
		"regen20": 0.5,
		"regen57": 0.75,
		"cap40": 50,
		"thresholds": [5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 57],
		"rewards": {5: 20, 10: 25, 15: 30, 20: 40, 25: 50, 30: 60,
			35: 70, 40: 80, 45: 90, 50: 100, 55: 120, 57: 160},
	},
	"resonance": {
		"miles": [10, 50, 100],
		"regen10": 0.03,
		"cap50": 5,
		"claim_gate_msec": 15000,
	},
	"letters": {
		"mile_every": 5,
		"cap_each": 3,
		"pending_max": 20,
	},
	"atlas": {
		"mile_every": 10,
		"cap_each": 3,
		"pending_max": 20,
	},
	"circle": {
		"hearth_base": 10,
		"day_miles": [7, 30, 100, 365],
		"day_cap": {7: 5, 100: 10},
		"day_regen": {30: 0.05},
		"pts_miles": [50, 150, 500],
		"pts_cap": {50: 3, 500: 5},
		"pts_regen": {150: 0.03},
		"ranks": [
			{"level": 1, "kind": "дней",  "threshold": 7,   "title": "Искра",     "shape": "dot",      "color": "#ffe08a"},
			{"level": 2, "kind": "дней",  "threshold": 30,  "title": "Уголёк",    "shape": "circle",   "color": "#e88a3c"},
			{"level": 3, "kind": "очков", "threshold": 50,  "title": "Тлеющий",   "shape": "triangle", "color": "#e05252"},
			{"level": 4, "kind": "дней",  "threshold": 100, "title": "Полено",    "shape": "square",   "color": "#a03028"},
			{"level": 5, "kind": "очков", "threshold": 150, "title": "Горящий",   "shape": "diamond",  "color": "#ff6a3c"},
			{"level": 6, "kind": "дней",  "threshold": 365, "title": "Сердце",    "shape": "star",     "color": "#ffd21f"},
			{"level": 7, "kind": "очков", "threshold": 500, "title": "Пламенный", "shape": "flame",    "color": "#fff4d6"},
		],
		"decor_rewards": {30: "planetarium_ember", 100: "door_guild", 365: "bed_carved"},
	},
	"vein": {
		"streak_cap": 5,
		"streak_reward": 25,
		"points_world": 2,
	},
	"fair": {
		"regen_each": 0.05,
		"regen_cap": 0.5,
		"offline_goal": 3,
		"offline_factor": 0.5,
	},
	"spring": {
		"version": 1,
		"base_interval": 6.0,
		"min_interval": 0.5,
		"speed_factor": 0.85,
		"speed": [
			{"ether": 30,  "materials": {"stone": 12}},
			{"ether": 45,  "materials": {"brick": 20}},
			{"ether": 65,  "materials": {"metal": 16}},
			{"ether": 85,  "materials": {"glass": 20, "obsidian": 8}},
			{"ether": 105, "materials": {"crystal": 14}},
			{"ether": 125, "materials": {"gold": 12}},
			{"ether": 140, "materials": {"tool": 10, "crystal": 12}},
		],
		"volume": [
			{"ether": 30,  "materials": {"stone": 12}},
			{"ether": 45,  "materials": {"clay": 18}},
			{"ether": 60,  "materials": {"stone": 40}},
			{"ether": 80,  "materials": {"metal": 18}},
			{"ether": 100, "materials": {"glass": 22}},
			{"ether": 120, "materials": {"crystal": 16}},
			{"ether": 150, "materials": {"gold": 12, "tool": 10}},
		],
		"volume_cap": [100, 250, 600, 1500, 4000, 10000, 25000, 60000],
		"sources": [
			{"ether": 90,  "materials": {"metal": 25, "glass": 12},  "req": {"speed": 3}},
			{"ether": 130, "materials": {"crystal": 20, "gold": 12}, "req": {"speed": 5}},
			{"ether": 170, "materials": {"tool": 18, "crystal": 22}, "req": {"speed": 6}},
		],
		"offline": [
			{"ether": 60,  "materials": {"brick": 30},               "req": {"volume": 3}},
			{"ether": 90,  "materials": {"metal": 20, "glass": 14},  "req": {"volume": 4}},
			{"ether": 120, "materials": {"crystal": 18, "gold": 12}, "req": {"volume": 5}},
		],
		"offline_window_sec": [300.0, 3600.0, 14400.0, 43200.0],
		"material_tier": {
			"stone": 0, "clay": 0, "brick": 0, "metal": 1, "glass": 1,
			"obsidian": 2, "crystal": 3, "gold": 3, "tool": 4,
		},
	},
	"workshop": {
		"version": 1,
		"invalid_depth": 1 << 29,
		"max_xp": 2147483647,
		"xp_per_synthesis_max": 6,
		"ranks": [
			{"name": "Подмастерье", "xp": 0,    "lines": 1, "capacity": 1, "ether": 0,   "materials": {}},
			{"name": "Мастер",      "xp": 100,  "lines": 2, "capacity": 2, "ether": 120, "materials": {"brick": 20, "metal": 10}},
			{"name": "Инженер",     "xp": 400,  "lines": 3, "capacity": 3, "ether": 240, "materials": {"glass": 25, "tool": 10}},
			{"name": "Архитектор",  "xp": 1000, "lines": 4, "capacity": 4, "ether": 480, "materials": {"crystal": 20, "gold": 10}},
		],
		"autonomy": [
			{"rank": 0, "stages": 60,  "ether": 0,   "materials": {}},
			{"rank": 1, "stages": 120, "ether": 150, "materials": {"glass": 15, "metal": 10}},
			{"rank": 2, "stages": 240, "ether": 300, "materials": {"tool": 15, "crystal": 10}},
		],
		"statuses": ["idle", "running", "paused_user", "waiting_ether", "waiting_ingredients", "waiting_recipe", "waiting_inventory"],
	},
	"retort": {
		"base_hours": 8.0,
		"tier_hours_factor": 0.5,
		"slot_max": 4,
		"legacy_cap_each": 1,
		"legacy_cap_first": 8,
		"materials": ["stone", "clay", "brick", "metal", "glass", "obsidian", "crystal", "gold", "tool"],
		"element_by_category": {"огонь": "fire", "вода": "water", "воздух": "air", "земля": "earth"},
		"element_by_sub": {"light": "fire", "fulgurite": "fire", "wine": "fire",
			"stream": "water", "fruit": "water", "dye": "air"},
		"queue_depth": [1, 2, 3, 4, 6, 8],
		"offline_window_sec": [28800.0, 43200.0, 86400.0, 129600.0, 172800.0, 259200.0],
		"speed_factor": [1.0, 0.9, 0.8, 0.7, 0.6, 0.5],
		"complexity_max_tier": [1, 2, 3, 4, 4],
		"queue": [
			{"essences": {"fire-0": 3, "water-0": 3}},
			{"essences": {"earth-1": 3, "air-1": 3}},
			{"essences": {"fire-2": 2, "water-2": 2, "earth-2": 2}},
			{"essences": {"air-3": 3, "fire-3": 3}},
			{"essences": {"blend-fire": 2, "blend-water": 2}},
		],
		"offline": [
			{"essences": {"water-0": 4, "earth-0": 4}},
			{"essences": {"air-1": 4, "fire-1": 4}},
			{"essences": {"water-2": 3, "earth-2": 3}},
			{"essences": {"air-3": 3, "water-3": 3}},
			{"essences": {"blend-earth": 2, "blend-air": 2}},
		],
		"slots": [
			{"essences": {"earth-0": 5, "fire-0": 5}},
			{"essences": {"water-1": 5, "air-1": 5}},
			{"essences": {"earth-3": 4, "fire-3": 4}},
		],
		"speed": [
			{"essences": {"fire-1": 4, "air-0": 4}},
			{"essences": {"water-2": 4, "earth-1": 4}},
			{"essences": {"fire-3": 3, "air-3": 3}},
			{"essences": {"water-4": 3, "earth-4": 3}},
			{"essences": {"blend-fire": 2, "blend-air": 2}},
		],
		"complexity": [
			{"essences": {"earth-1": 4, "water-1": 4}},
			{"essences": {"fire-2": 4, "air-2": 4}},
			{"essences": {"earth-3": 3, "water-3": 3}},
			{"essences": {"fire-4": 3, "air-4": 3}},
			{"essences": {"earth-4": 3, "water-4": 3}},
		],
	},
	"essences": {
		"blend_base_hours": 12.0,
		"blend_upgraded_factor": 0.6,
		"blend": [
			{"essences": {"fire-4": 2, "water-4": 2, "earth-4": 2, "air-4": 2}, "req": {"complexity": 5}},
			{"essences": {"blend-fire": 1, "blend-water": 1, "blend-earth": 1, "blend-air": 1}},
		],
		"cap": [
			{"cap": 30, "essences": {"earth-2": 3, "water-2": 3}},
			{"cap": 40, "essences": {"fire-3": 3, "air-3": 3}},
			{"cap": 50, "essences": {"earth-3": 3, "water-3": 3}},
			{"cap": 60, "essences": {"fire-4": 3, "air-4": 3}},
			{"cap": 80, "essences": {"blend-earth": 2, "blend-fire": 2}},
		],
		"equip": [
			{"lines": 1,    "essences": {"fire-3": 3, "water-3": 3, "earth-3": 3}},
			{"speed": 0.85, "essences": {"air-4": 3, "fire-4": 3, "water-4": 3}},
			{"lines": 1,    "essences": {"blend-fire": 2, "blend-water": 2, "blend-earth": 2, "blend-air": 2}},
		],
		"blend_recipes": {
			"fire": ["fire-3", "fire-4"], "water": ["water-3", "water-4"],
			"earth": ["earth-3", "earth-4"], "air": ["air-3", "air-4"],
		},
	},
	"sigils": {
		"set_cap_bonus": 40,
		"set_craft_factor": 0.9,
		"set_speed_factor": 0.5,
		"card_speed_pct": {"common": 0.25, "rare": 0.75, "epic": 1.25, "legendary": 2.0},
		"card_cap": {"common": 1.25, "rare": 3.75, "epic": 6.25, "legendary": 10.0},
		"card_autonomy": {"common": 0.5, "rare": 1.25, "epic": 2.5, "legendary": 3.75},
		"chroma_speed_share": 0.5,
	},
	"progression": {
		"achievement_cap": 2,
		"achievement_regen": 0.015,
		"quest_cap": 6,
		"quest_regen": 0.03,
	},
	"player": {
		"action_seconds": 1.0,
	},
}

const NON_CALIBRATION_PATHS := {
	"sync.schema_version": {"type": "int", "min": 4, "max": 4, "calibration_safe": false},
	"sync.max_accrual_rate_per_sec": {"type": "float", "min": 1000.0, "max": 1000.0, "calibration_safe": false},
	"spring.version": {"type": "int", "min": 1, "max": 1, "calibration_safe": false},
	"spring.min_interval": {"type": "float", "min": 0.5, "max": 0.5, "calibration_safe": false},
	"workshop.version": {"type": "int", "min": 1, "max": 1, "calibration_safe": false},
	"workshop.invalid_depth": {"type": "int", "min": 1 << 29, "max": 1 << 29, "calibration_safe": false},
	"workshop.max_xp": {"type": "int", "min": 2147483647, "max": 2147483647, "calibration_safe": false},
	"discovery.arity_min": {"type": "int", "min": 2, "max": 2, "calibration_safe": false},
	"discovery.arity_max": {"type": "int", "min": 2, "max": 2, "calibration_safe": false},
	"caps.craft_plan_hard_limit_operations": {"type": "int", "min": 200, "max": 200, "calibration_safe": false},
	"caps.craft_inventory_stack_cap": {"type": "int", "min": 1000000, "max": 1000000, "calibration_safe": false},
	"retort.slot_max": {"type": "int", "min": 4, "max": 4, "calibration_safe": false},
}

static var _allowed_cache: Dictionary = {}


static func baseline() -> BalanceProfile:
	var data: Dictionary = BASELINE_DATA.duplicate(true)
	var h: String = _hash_dict(data)
	return BalanceProfile.new(data, {
		"schema": SCHEMA_VERSION,
		"name": "baseline",
		"base": "baseline",
		"resolved_overrides": {},
		"hash": h,
	})


static func profile_hash(profile: BalanceProfile) -> String:
	if profile == null:
		return ""
	return _hash_dict(profile.raw_data())


static func allowed_parameters() -> Dictionary:
	if not _allowed_cache.is_empty():
		return _allowed_cache.duplicate(true)
	var out: Dictionary = NON_CALIBRATION_PATHS.duplicate(true)
	_collect_numeric_specs(BASELINE_DATA, "", out)
	_allowed_cache = out
	return out.duplicate(true)


static func validate_overrides(overrides: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	var specs: Dictionary = allowed_parameters()
	for raw_k in overrides:
		var path := String(raw_k)
		if not specs.has(path):
			errs.append("unknown override path: " + path)
			continue
		var spec: Dictionary = specs[path]
		if not bool(spec.get("calibration_safe", false)):
			errs.append("non-calibration-safe path: " + path)
			continue
		var v: Variant = overrides[raw_k]
		var vt := typeof(v)
		if vt == TYPE_BOOL or (vt != TYPE_INT and vt != TYPE_FLOAT):
			errs.append("wrong type for %s" % path)
			continue
		var fv := float(v)
		if is_nan(fv) or is_inf(fv):
			errs.append("non-finite value for %s" % path)
			continue
		if String(spec.get("type", "")) == "int":
			if vt == TYPE_FLOAT and not is_equal_approx(fv, round(fv)):
				errs.append("non-integer float for int path %s" % path)
				continue
		if fv < float(spec["min"]) - 1e-9 or fv > float(spec["max"]) + 1e-9:
			errs.append("out of range for %s: %s not in [%s, %s]" % [path, str(v), str(spec["min"]), str(spec["max"])])
	return errs


static func resolve(overrides: Dictionary, profile_name: String = "custom") -> BalanceProfile:
	var errs := validate_overrides(overrides)
	if not errs.is_empty():
		push_error("BalanceConfig.resolve rejected overrides: " + "; ".join(errs))
		return null
	var data: Dictionary = BASELINE_DATA.duplicate(true)
	var specs: Dictionary = allowed_parameters()
	var resolved: Dictionary = {}
	var keys: Array = overrides.keys()
	keys.sort()
	for k in keys:
		var path := String(k)
		var spec: Dictionary = specs[path]
		var coerced: Variant = int(round(float(overrides[k]))) if String(spec["type"]) == "int" else float(overrides[k])
		_set_path(data, path, coerced)
		resolved[path] = coerced
	var h := _hash_dict(data)
	return BalanceProfile.new(data, {
		"schema": SCHEMA_VERSION,
		"name": "baseline" if resolved.is_empty() and profile_name == "custom" else profile_name,
		"base": "baseline",
		"resolved_overrides": resolved,
		"hash": h,
	})


static func validate_profile_document(raw: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	for req_k in ["schema", "name", "base", "overrides"]:
		if not raw.has(req_k):
			errs.append("missing required key: " + req_k)
	if not errs.is_empty():
		return errs
	var sc_v: Variant = raw["schema"]
	if (typeof(sc_v) != TYPE_INT and typeof(sc_v) != TYPE_FLOAT) or typeof(sc_v) == TYPE_BOOL or int(round(float(sc_v))) != SCHEMA_VERSION:
		errs.append("unsupported schema: " + str(sc_v))
	if not (raw["name"] is String) or String(raw["name"]).strip_edges().is_empty():
		errs.append("invalid profile name")
	if not (raw["base"] is String) or String(raw["base"]) != "baseline":
		errs.append("unsupported base: " + str(raw["base"]))
	if not (raw["overrides"] is Dictionary):
		errs.append("overrides must be a Dictionary")
		return errs
	var ov_errs := validate_overrides(raw["overrides"] as Dictionary)
	for e in ov_errs:
		errs.append(e)
	return errs


static func load_profile_json(path: String) -> BalanceProfile:
	if path.is_empty() or not FileAccess.file_exists(path):
		push_error("BalanceConfig.load_profile_json: file not found: " + path)
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.find("NaN") != -1 or text.find("Infinity") != -1:
		push_error("BalanceConfig.load_profile_json: non-finite token in " + path)
		return null
	var parser := JSON.new()
	if parser.parse(text) != OK or not (parser.data is Dictionary):
		push_error("BalanceConfig.load_profile_json: malformed JSON in " + path)
		return null
	var doc: Dictionary = parser.data
	var errs := validate_profile_document(doc)
	if not errs.is_empty():
		push_error("BalanceConfig.load_profile_json invalid document %s: %s" % [path, "; ".join(errs)])
		return null
	return resolve(doc["overrides"] as Dictionary, String(doc["name"]).strip_edges())


static func _collect_numeric_specs(node: Variant, prefix: String, out: Dictionary) -> void:
	if out.has(prefix):
		return
	if node is Dictionary:
		var d: Dictionary = node
		for k in d:
			var k_str := str(k)
			var sub := k_str if prefix.is_empty() else (prefix + "." + k_str)
			if k_str in ["req", "level", "threshold", "material_tier", "decor_rewards", "thresholds", "miles", "day_miles", "pts_miles", "stage_ranks", "complexity_max_tier"] or k_str == "rank" and prefix.begins_with("workshop.autonomy."):
				out[sub] = {"type": "locked", "min": 0, "max": 0, "calibration_safe": false}
				continue
			_collect_numeric_specs(d[k], sub, out)
	elif node is Array:
		var a: Array = node
		for i in range(a.size()):
			var sub := "%s.%d" % [prefix, i]
			_collect_numeric_specs(a[i], sub, out)
	elif typeof(node) == TYPE_INT:
		var iv: int = int(node)
		var lo: int = 1 if prefix.ends_with("interval") or prefix.ends_with("max") or prefix.ends_with("stages") or prefix.ends_with("lines") or prefix.ends_with("capacity") or prefix.ends_with("cap") else 0
		var hi: int = maxi(iv * 10, 100)
		out[prefix] = {"type": "int", "min": lo, "max": hi, "calibration_safe": true}
	elif typeof(node) == TYPE_FLOAT:
		var fv: float = float(node)
		var lo_f: float = 0.05 if (prefix.ends_with("interval") or prefix.ends_with("hours") or prefix.ends_with("factor") or prefix.ends_with("growth") or prefix.ends_with("sec") or prefix.ends_with("seconds") or prefix.begins_with("retort.speed_factor.") or prefix.begins_with("essences.equip.") and prefix.ends_with("speed")) else 0.0
		if prefix.ends_with("seconds"):
			lo_f = 0.000001
		var hi_f: float = maxf(fv * 10.0, 10.0)
		out[prefix] = {"type": "float", "min": lo_f, "max": hi_f, "calibration_safe": true}


static func _set_path(root: Dictionary, path: String, value: Variant) -> void:
	var parts := path.split(".")
	var cur: Variant = root
	for i in range(parts.size() - 1):
		var p := parts[i]
		if cur is Dictionary:
			var d: Dictionary = cur
			cur = d[p] if d.has(p) else d[int(p)]
		elif cur is Array:
			cur = (cur as Array)[int(p)]
	var last := parts[parts.size() - 1]
	if cur is Dictionary:
		var d2: Dictionary = cur
		if d2.has(last):
			d2[last] = value
		elif last.is_valid_int() and d2.has(int(last)):
			d2[int(last)] = value
		else:
			d2[last] = value
	elif cur is Array:
		(cur as Array)[int(last)] = value


static func _hash_dict(d: Dictionary) -> String:
	return JSON.stringify(_canon(d), "", true).sha256_text()


static func _canon(v: Variant) -> Variant:
	if v is Dictionary:
		var d: Dictionary = v
		var out: Dictionary = {}
		var ks: Array = []
		for k in d:
			ks.append(str(k))
		ks.sort()
		for ks_item in ks:
			var s_key: String = str(ks_item)
			var orig_k: Variant = s_key if d.has(s_key) else int(s_key)
			out[s_key] = _canon(d[orig_k])
		return out
	if v is Array:
		var a: Array = v
		var arr: Array = []
		for item in a:
			arr.append(_canon(item))
		return arr
	if typeof(v) == TYPE_FLOAT:
		return snappedf(float(v), 1e-6)
	return v
