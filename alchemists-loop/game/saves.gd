extends RefCounted
class_name Saves
# Сейвы и возвращение (R10): сохранение/загрузка, офлайн-доход, попап возвращения.
# Своё состояние — поля ниже; общее — через g (ноду Game).

var g: Game

var _return_elapsed := 0.0
var _return_ether := 0
var _return_spring := 0
var _return_spring_name := ""
var _return_craft_steps := 0
var _return_craft_status := ""
var _return_world_new := -1
var _return_rank_old := -1
var _return_open := false
var _return_shown := false
var _return_dim: ColorRect = null
var _return_popup: CenterContainer = null
var _return_list: VBoxContainer = null

func _init(game: Game) -> void:
	g = game

# ================= сейвы =================

func _save_game() -> void:
	var data := {
		"version": Game.SAVE_VERSION,
		"ether": g._engine.ether,
		"ether_overflow": g._engine.ether_overflow,
		"mastery_rank": g._engine.mastery_rank,
		"experiment_day": g._engine._experiment_day,
		"experiment_count": g._engine._experiment_count,
		"experiment_last_at": g._engine._experiment_last_at,
		"experiment_pending_pair": g._engine._experiment_pending_pair,
		"craft_job": g._engine._craft_job,
		"blueprints": g._engine._blueprints,
		"inventory": g._engine.inventory,
		"known_recipes": g._engine.known_recipes.keys(),
		"attempts": g._engine.attempts,
		"successes": g._engine.successes,
		"upgrades": g._engine.upgrades,
		"spring_source": g._engine.spring_source,
		"spring_on": g._engine.spring_on,
		"bench_target": g._pages._bench_target,
		"bench_on": g._pages._bench_on,
		"spirit_name": g._spirit._spirit_name,
		"player_name": g._spirit._player_name,
		"net_nick": g._online._net_nick,
		"milestones": g._engine._milestones_done.keys(),
		"quests_done": g._guild._quests_done.keys(),
		"quest_brew": g._guild._quest_brew,
		"quest_tier": g._guild._quest_tier,
		"quest_challenge": g._guild._quest_challenge,
		"ach_done": g._progress_ui._ach_done.keys(),
		"ach_world_first": g._progress_ui._ach_world_first,
		"res_done": g._resonance._res_done.keys(),
		"res_total": g._resonance._res_total,
		"res_balance": g._resonance._res_balance,
		"retort_slots": g._retort._retort_slots,
		"essences": g._retort._essences,
		"last_rank": g._last_rank,
		"world_total_seen": g._online._world_total_seen,
		"letter_milestones": g._riddles._letter_milestones,
		"letter_solved_total": g._riddles._letter_solved_total,
		"letter_pending": g._riddles._letter_pending,
		"letter_cache": {"today": g._riddles._letter_today, "backlog": g._riddles._letter_backlog},
		"atlas_milestones": g._riddles._atlas_milestones,
		"atlas_solved_total": g._riddles._atlas_solved_total,
		"atlas_pending": g._riddles._atlas_pending,
		"atlas_cache": {"today": g._riddles._atlas_today, "history": g._riddles._atlas_history},
		"set_done": g._progress_ui._set_done.keys(),
		"order_day": g._guild._order_day,
		"order_targets": g._guild._order_targets_cache,
		"order_done": g._guild._order_done.keys(),
		"last_ts": Time.get_unix_time_from_system(),
		"sage_gold": g._engine.sage_gold,
		"journal": g._hub._log_events.slice(0, 20),
		"music_on": Sfx.music_on,
		"sfx_vol": Sfx.sfx_volume,
		"music_vol": Sfx.music_volume,
		"server_layers": g._online._server_layers,
		"server_elements": g._online._server_elements,
		"server_recipes": g._online._server_recipes,
		"companion_met": g._spirit._companion_met,
		"companion_affinity": g._spirit._companion_affinity,
		"cosmetic_theme": g._home._cosmetic_theme,
		"cosmetic_aura": g._home._cosmetic_aura,
		"cosmetic_house": g._home._cosmetic_house,
		"companion_unlocked": g._spirit._companion_unlocked,
		"house_furniture": g._home.house_furniture,
		"house_layout": g._home.house_layout,
		"house_owned": g._home.house_owned,
		"house_visited_day": g._home.house_visited_day,
		"house_gift_week": g._home.house_gift_week,
		"house_gift_count": g._home.house_gift_count,
		"house_tasks_done": g._home.house_tasks_done,
		"theme_custom_on": g._home._theme_custom_on,
		"theme_custom": "#" + g._home._theme_custom.to_html(false),
		"aura_custom_on": g._home._aura_custom_on,
		"aura_custom": "#" + g._home._aura_custom.to_html(false),
		"wall_hex": "#" + g._home._cosmetic_wall.to_html(false),
		"floor_hex": "#" + g._home._cosmetic_floor.to_html(false),
		"custom_unlocked": g._home._custom_unlocked,
		"circle_days": g._retention._circle_days,
		"circle_run": g._retention._circle_run,
		"circle_last": g._retention._circle_last,
		"hearth_claim": g._retention._hearth_claim,
		"circle_disc_day": g._retention._circle_disc_day,
		"circle_disc": g._retention._circle_disc,
		"circle_reward_day": g._retention._circle_reward_day,
		"circle_pts_total": g._retention._circle_pts_total,
		"circle_mdays": g._retention._circle_mdays,
		"circle_mpts": g._retention._circle_mpts,
		"circle_hint": g._retention._circle_hint,
		"circle_mine": g._retention._circle_mine,
		"week_cache": g._retention._week_cache,
		"vein_cap_total": g._retention._vein_cap_total,
		"fair_regen_total": g._retention._fair_regen_total
	}
	var file := FileAccess.open(g.TEMP_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Не удалось открыть временный файл сохранения.")
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file.close()
	var save_abs := ProjectSettings.globalize_path(g.SAVE_PATH)
	var temp_abs := ProjectSettings.globalize_path(g.TEMP_PATH)
	var backup_abs := ProjectSettings.globalize_path(g.BACKUP_PATH)
	if FileAccess.file_exists(g.SAVE_PATH):
		if FileAccess.file_exists(g.BACKUP_PATH):
			if DirAccess.remove_absolute(backup_abs) != OK:
				push_warning("Не удалось обновить backup.")
				return
		if DirAccess.rename_absolute(save_abs, backup_abs) != OK:
			push_warning("Не удалось создать backup.")
			return
	if DirAccess.rename_absolute(temp_abs, save_abs) != OK:
		push_warning("Не удалось установить новое сохранение.")
		if FileAccess.file_exists(g.BACKUP_PATH):
			DirAccess.rename_absolute(backup_abs, save_abs)

func _load_game() -> void:
	var data := _read_save(g.SAVE_PATH)
	if data.is_empty():
		data = _read_save(g.BACKUP_PATH)
	if data.is_empty():
		return
	# U9 (T12): загрузка заменяет мир под возможными сонными корутинами —
	# то же поколение сбросов, что у престижа и новой игры.
	g._engine.brew_epoch += 1
	g._engine.upgrades.clear()
	if data.get("upgrades") is Dictionary:
		for raw_id in data["upgrades"]:
			var uid := String(raw_id)
			if g._engine._up_def(uid).is_empty():
				continue
			g._engine.upgrades[uid] = clampi(int(data["upgrades"][raw_id]), 0, int(g._engine._up_def(uid)["max"]))
	if data.get("spring_source") is String:
		var ss := String(data["spring_source"])
		if ss in Game.BASE_IDS:
			g._engine.spring_source = ss
	g._engine.spring_on = bool(data.get("spring_on", false))
	if data.get("bench_target") is String:
		var bt := String(data["bench_target"])
		if g.ITEMS.has(bt):
			g._pages._bench_target = bt
	g._pages._bench_on = bool(data.get("bench_on", false)) and g._pages._bench_target != ""
	if data.get("spirit_name") is String:
		g._spirit._spirit_name = String(data["spirit_name"])
	if data.get("player_name") is String:
		g._spirit._player_name = String(data["player_name"])
	if data.get("net_nick") is String:
		var nn := g._hub._clean_player_nick(String(data["net_nick"]))
		if nn != "":
			g._online._net_nick = nn
	if data.get("milestones") is Array:
		g._engine._milestones_done.clear()
		for m in data["milestones"]:
			var mi := int(m)
			if Game.MILESTONES.has(mi):
				g._engine._milestones_done[mi] = true
	if data.get("server_layers") is Dictionary:
		for k in data["server_layers"]:
			g._online._server_layers[String(k)] = int(data["server_layers"][k])
	g._online._restore_server_elements(data.get("server_elements"))
	g._online._restore_server_recipes(data.get("server_recipes"))
	g._guild._quests_done.clear()
	if data.get("quests_done") is Array:
		for qid in data["quests_done"]:
			g._guild._quests_done[String(qid)] = true
	g._guild._quest_brew.clear()
	if data.get("quest_brew") is Dictionary:
		for k in data["quest_brew"]:
			g._guild._quest_brew[String(k)] = int(data["quest_brew"][k])
	g._guild._quest_tier.clear()
	if data.get("quest_tier") is Dictionary:
		for k in data["quest_tier"]:
			g._guild._quest_tier[int(k)] = int(data["quest_tier"][k])
	g._guild._quest_challenge = maxi(0, int(data.get("quest_challenge", 0)))
	g._progress_ui._ach_done.clear()
	if data.get("ach_done") is Array:
		for aid in data["ach_done"]:
			g._progress_ui._ach_done[String(aid)] = true
	g._progress_ui._ach_world_first = maxi(0, int(data.get("ach_world_first", 0)))
	g._resonance._res_done.clear()
	if data.get("res_done") is Array:
		for m in data["res_done"]:
			var mi := int(m)
			if Game.RES_MILES.has(mi):
				g._resonance._res_done[mi] = true
	g._resonance._res_total = maxi(0, int(data.get("res_total", 0)))
	g._resonance._res_balance = maxi(0, int(data.get("res_balance", 0)))
	if data.get("retort_slots") is Array:
		_load_retort_slots_for_test(data["retort_slots"] as Array)
	else:
		_load_retort_slots_for_test([])
	g._retort._essences.clear()
	if data.get("essences") is Dictionary:
		for k in data["essences"]:
			g._retort._essences[String(k)] = String(data["essences"][k])
	g._last_rank = maxi(0, int(data.get("last_rank", 0)))
	g._online._world_total_seen = maxi(0, int(data.get("world_total_seen", 0)))
	g._riddles._letter_milestones = maxi(0, int(data.get("letter_milestones", 0)))
	g._riddles._letter_solved_total = maxi(0, int(data.get("letter_solved_total", 0)))
	g._riddles._letter_pending = data.get("letter_pending", [])
	if g._riddles._letter_pending == null or typeof(g._riddles._letter_pending) != TYPE_ARRAY:
		g._riddles._letter_pending = []
	var lcache: Dictionary = data.get("letter_cache", {})
	if lcache == null or typeof(lcache) != TYPE_DICTIONARY:
		lcache = {}
	g._riddles._letter_today = lcache.get("today", {})
	if g._riddles._letter_today == null or typeof(g._riddles._letter_today) != TYPE_DICTIONARY:
		g._riddles._letter_today = {}
	g._riddles._letter_backlog = lcache.get("backlog", [])
	if g._riddles._letter_backlog == null or typeof(g._riddles._letter_backlog) != TYPE_ARRAY:
		g._riddles._letter_backlog = []
	g._riddles._atlas_milestones = maxi(0, int(data.get("atlas_milestones", 0)))
	g._riddles._atlas_solved_total = maxi(0, int(data.get("atlas_solved_total", 0)))
	g._riddles._atlas_pending = data.get("atlas_pending", [])
	if g._riddles._atlas_pending == null or typeof(g._riddles._atlas_pending) != TYPE_ARRAY:
		g._riddles._atlas_pending = []
	var acache: Dictionary = data.get("atlas_cache", {})
	if acache == null or typeof(acache) != TYPE_DICTIONARY:
		acache = {}
	g._riddles._atlas_today = acache.get("today", {})
	if g._riddles._atlas_today == null or typeof(g._riddles._atlas_today) != TYPE_DICTIONARY:
		g._riddles._atlas_today = {}
	g._riddles._atlas_history = acache.get("history", [])
	if g._riddles._atlas_history == null or typeof(g._riddles._atlas_history) != TYPE_ARRAY:
		g._riddles._atlas_history = []
	g._progress_ui._set_done.clear()
	if data.get("set_done") is Array:
		for cat in data["set_done"]:
			g._progress_ui._set_done[String(cat)] = true
	if data.get("order_day") is String:
		g._guild._order_day = String(data["order_day"])
	if data.get("order_targets") is Array:
		g._guild._order_targets_cache.clear()
		for t in data["order_targets"]:
			g._guild._order_targets_cache.append(String(t))
	g._guild._order_done.clear()
	if data.get("order_done") is Array:
		for t in data["order_done"]:
			g._guild._order_done[String(t)] = true
	g._last_ts = maxf(0.0, float(data.get("last_ts", 0.0)))
	g._hub._log_events.clear()
	if data.get("journal") is Array:
		for e in data["journal"]:
			if typeof(e) == TYPE_DICTIONARY:
				g._hub._log_events.append(e)
	if data.get("music_on") is bool:
		if bool(data["music_on"]) != Sfx.music_on:
			Sfx.toggle_music()
	Sfx.set_sfx_volume(clampf(float(data.get("sfx_vol", 1.0)), 0.0, 1.0))
	Sfx.set_music_volume(clampf(float(data.get("music_vol", 1.0)), 0.0, 1.0))
	g._engine.sage_gold = maxi(0, int(data.get("sage_gold", 0)))
	g._spirit._companion_met = bool(data.get("companion_met", false))
	g._spirit._companion_affinity = maxi(0, int(data.get("companion_affinity", 0)))
	if data.get("cosmetic_theme") is String:
		g._home._cosmetic_theme = String(data["cosmetic_theme"])
	if data.get("cosmetic_aura") is String:
		g._home._cosmetic_aura = String(data["cosmetic_aura"])
	g._home._cosmetic_house = bool(data.get("cosmetic_house", false))
	g._home.house_furniture.clear()
	if data.get("house_furniture") is Dictionary:
		for k in data["house_furniture"]:
			var cat := String(k)
			var vid := String(data["house_furniture"][k])
			if not g._home._decor_cat(cat).is_empty() and not g._home._decor_item(cat, vid).is_empty():
				g._home.house_furniture[cat] = vid
	elif data.get("house_furniture") is Array:
		# старый сейв: плоский список категорий → дефолтный вариант каждой
		for fid in data["house_furniture"]:
			var fs := String(fid)
			if not g._home._decor_cat(fs).is_empty():
				g._home.house_furniture[fs] = fs
	g._home.house_layout.clear()
	if data.get("house_layout") is Dictionary:
		for k in data["house_layout"]:
			var lcat := String(k)
			if g._home._decor_cat(lcat).is_empty():
				continue
			var lpos = data["house_layout"][k]
			if lpos is Array and lpos.size() >= 2:
				g._home.house_layout[lcat] = [clampf(float(lpos[0]), -0.25, 1.25), clampf(float(lpos[1]), -0.25, 1.25)]
	g._home.house_owned.clear()
	if data.get("house_owned") is Dictionary:
		for k in data["house_owned"]:
			var ocat := String(k)
			if g._home._decor_cat(ocat).is_empty():
				continue
			var oarr: Array = []
			if data["house_owned"][k] is Array:
				for v in data["house_owned"][k]:
					var ovid := String(v)
					if not g._home._decor_item(ocat, ovid).is_empty() and not oarr.has(ovid):
						oarr.append(ovid)
			g._home.house_owned[ocat] = oarr
	# γ: локальный кэш визитов — словарь nick -> "YYYY-MM-DD"; фильтр по строковым
	# ключам-никнеймам, как у house_owned по категориям
	g._home.house_visited_day.clear()
	if data.get("house_visited_day") is Dictionary:
		for k in data["house_visited_day"]:
			var vnick := String(k)
			if vnick != "":
				g._home.house_visited_day[vnick] = String(data["house_visited_day"][k])
	g._home.house_gift_week = String(data.get("house_gift_week", ""))
	g._home.house_gift_count = maxi(0, int(data.get("house_gift_count", 0)))
	g._home.house_tasks_done.clear()
	if data.get("house_tasks_done") is Array:
		for raw_tid in data["house_tasks_done"]:
			var tid := String(raw_tid)
			for t in Game.HOUSE_TASKS:
				if String(t["id"]) == tid and not g._home.house_tasks_done.has(tid):
					g._home.house_tasks_done.append(tid)
	# миграция: текущая расстановка считается купленной
	for fcat in g._home.house_furniture:
		g._home._own_item(String(fcat), String(g._home.house_furniture[fcat]))
	g._home._theme_custom_on = bool(data.get("theme_custom_on", false))
	if typeof(data.get("theme_custom")) == TYPE_STRING:
		g._home._theme_custom = g._home._color_from_hex(String(data["theme_custom"]), Color("#0d1219"))
	g._home._aura_custom_on = bool(data.get("aura_custom_on", false))
	if typeof(data.get("aura_custom")) == TYPE_STRING:
		g._home._aura_custom = g._home._color_from_hex(String(data["aura_custom"]), Color("#ffb85c"))
	if typeof(data.get("wall_hex")) == TYPE_STRING:
		g._home._cosmetic_wall = g._home._color_from_hex(String(data["wall_hex"]), Color("#5a4d40"))
	if typeof(data.get("floor_hex")) == TYPE_STRING:
		g._home._cosmetic_floor = g._home._color_from_hex(String(data["floor_hex"]), Color("#5d452f"))
	g._home._custom_unlocked.clear()
	if data.get("custom_unlocked") is Dictionary:
		for k in data["custom_unlocked"]:
			if bool(data["custom_unlocked"][k]):
				g._home._custom_unlocked[String(k)] = true
	else:
		# старые сейвы: уже включённый кастом засчитываем как купленный
		if g._home._theme_custom_on:
			g._home._custom_unlocked["theme"] = true
		if g._home._aura_custom_on:
			g._home._custom_unlocked["aura"] = true
		if String(data.get("wall_hex", "")) != "":
			g._home._custom_unlocked["wall"] = true
		if String(data.get("floor_hex", "")) != "":
			g._home._custom_unlocked["floor"] = true
	g._retention._circle_days.clear()
	if data.get("circle_days") is Array:
		for d in data["circle_days"]:
			g._retention._circle_days.append(String(d))
	g._retention._circle_run = maxi(0, int(data.get("circle_run", 0)))
	g._retention._circle_last = String(data.get("circle_last", ""))
	g._retention._hearth_claim = String(data.get("hearth_claim", ""))
	g._retention._circle_disc_day = String(data.get("circle_disc_day", ""))
	g._retention._circle_disc = maxi(0, int(data.get("circle_disc", 0)))
	g._retention._circle_reward_day = String(data.get("circle_reward_day", ""))
	g._retention._circle_pts_total = maxi(0, int(data.get("circle_pts_total", 0)))
	g._retention._circle_mdays = clampi(int(data.get("circle_mdays", 0)), 0, Game.CIRCLE_DAY_MILES.size())
	g._retention._circle_mpts = clampi(int(data.get("circle_mpts", 0)), 0, Game.CIRCLE_PTS_MILES.size())
	g._retention._circle_hint = String(data.get("circle_hint", ""))
	g._retention._circle_mine = maxi(0, int(data.get("circle_mine", 0)))
	g._retention._week_cache = data.get("week_cache", {}) if data.get("week_cache", {}) is Dictionary else {}
	g._retention._vein_cap_total = maxi(0, int(data.get("vein_cap_total", 0)))
	g._retention._fair_regen_total = clampf(float(data.get("fair_regen_total", 0.0)), 0.0, Game.FAIR_REGEN_CAP)
	g._spirit._companion_apply_level()
	g._engine.ether_overflow = maxi(0, int(data.get("ether_overflow", 0)))
	g._engine.mastery_rank = maxi(0, int(data.get("mastery_rank", 0)))
	g._engine._experiment_day = String(data.get("experiment_day", ""))
	g._engine._experiment_count = clampi(int(data.get("experiment_count", 0)), 0, Game.EXPERIMENT_DAILY_LIMIT)
	g._engine._experiment_last_at = maxf(0.0, float(data.get("experiment_last_at", 0.0)))
	g._engine._experiment_pending_pair.clear()
	# U11 (T14): загрузка сейва аннулирует pending-записи прежней сессии —
	# их ответы не должны примениться к загруженному состоянию.
	g._online._pending_requests.clear()
	var saved_pending = data.get("experiment_pending_pair", [])
	if saved_pending is Array and saved_pending.size() == 2:
		var pending_a := String(saved_pending[0])
		var pending_b := String(saved_pending[1])
		if g.ITEMS.has(pending_a) and g.ITEMS.has(pending_b):
			g._engine._experiment_pending_pair = [pending_a, pending_b]
	var saved_job = data.get("craft_job", {})
	g._engine._craft_job = saved_job.duplicate(true) if saved_job is Dictionary else {}
	var saved_blueprints = data.get("blueprints", {})
	g._engine._blueprints = saved_blueprints.duplicate(true) if saved_blueprints is Dictionary else {}
	var saved_ether := maxi(0, int(data.get("ether", Game.START_ETHER)))
	var active_cap := g._engine._max_ether()
	g._engine.ether = clampi(saved_ether, 0, active_cap)
	# Old v1/v2 saves could contain more than the new active cap. Preserve that
	# value in the visible reserve instead of silently deleting it on migration.
	g._engine.ether_overflow += maxi(0, saved_ether - active_cap)
	g._engine.attempts = maxi(0, int(data.get("attempts", 0)))
	g._engine.successes = clampi(int(data.get("successes", 0)), 0, g._engine.attempts)
	var saved_inventory: Dictionary = data["inventory"]
	g._engine.inventory.clear()
	for raw_id in saved_inventory:
		var item_id := String(raw_id)
		if g.ITEMS.has(item_id):
			g._engine.inventory[item_id] = clampi(int(saved_inventory[raw_id]), 0, 1000000)
	for item_id in Game.BASE_IDS:
		if not g._engine.inventory.has(item_id):
			g._engine.inventory[item_id] = 0
	g._engine.known_recipes.clear()
	var saved_known: Array = data["known_recipes"]
	for recipe in g.RECIPES:
		var key := g._pair_key(String(recipe["a"]), String(recipe["b"]))
		if saved_known.has(key):
			g._engine.known_recipes[key] = true
	g._engine.known_recipes[g._pair_key("fire", "water")] = true
	g._engine.known_recipes[g._pair_key("earth", "fire")] = true
	if data.has("companion_unlocked"):
		g._spirit._companion_unlocked = bool(data["companion_unlocked"])
	else:
		# старый сейв: Светик открыт, если уже знаком или Искра уже в запасе
		g._spirit._companion_unlocked = g._spirit._companion_met or g._engine.inventory.has("spark")
	g._engine.status_text = "Лаборатория восстановлена. Продолжим эксперименты!"
	_grant_offline()
	g._progress_ui._ach_update()

func _load_retort_slots_for_test(raw: Array) -> void:
	# чтение массива retort_slots: тот же разбор, что в _load_game, вынесен в метод,
	# чтобы у сейва и теста u33 не появилось второе определение «валидного слота»
	g._retort._retort_slots.clear()
	for s in raw:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var sd := s as Dictionary
		g._retort._retort_slots.append({
			"sub": String(sd.get("sub", "")),
			"name": String(sd.get("name", "")),
			"started": maxf(0.0, float(sd.get("started", 0.0))),
			"dur": maxf(0.0, float(sd.get("dur", 0.0))),
		})
	while g._retort._retort_slots.size() < Game.RETORT_SLOT_MAX:
		g._retort._retort_slots.append({"sub": "", "name": "", "started": 0.0, "dur": 0.0})
	g._retort._retort_slots = g._retort._retort_slots.slice(0, Game.RETORT_SLOT_MAX)

func _offline_gain(elapsed: float, rate: float, cur: int, cap: int) -> int:
	# чистая формула офлайн-накопления (тестируется напрямую)
	if elapsed < Game.OFFLINE_MIN_SEC:
		return 0
	var eff := minf(elapsed, Game.OFFLINE_CAP_SEC)
	var gain := int(floor(eff * rate))
	if gain <= 0:
		return 0
	return mini(cap, cur + gain) - cur

func _spring_offline_gain(elapsed: float) -> int:
	# сколько Родник накапал бы за отсутствие (то же окно, что у эфира, но срез)
	if elapsed < Game.OFFLINE_MIN_SEC:
		return 0
	return mini(int(minf(elapsed, Game.OFFLINE_CAP_SEC) / Game.SPRING_INTERVAL), Game.SPRING_OFFLINE_MAX)

func _advance_craft_job_offline(elapsed: float) -> Dictionary:
	# Offline does not bypass the production operation cap. It advances at most
	# one resumable stage, preserving the same ingredients, ether costs and
	# intermediate outputs as the foreground runner.
	_return_craft_steps = 0
	_return_craft_status = ""
	if elapsed < Game.OFFLINE_MIN_SEC or g._engine._craft_job.is_empty():
		return {}
	var job: Dictionary = g._engine._craft_job
	var item_id := String(job.get("item", ""))
	if item_id == "":
		return {}
	var plan := g._guild._plan_craft(item_id)
	if not bool(plan.get("ok", false)):
		var frontier_plan := g._guild._plan_known_frontier(item_id)
		var frontier: Array = frontier_plan.get("frontier", [])
		var status := "recipe" if not frontier.is_empty() else "ingredients"
		job["status"] = "paused_" + status
		_return_craft_status = status
		return {"steps": 0, "status": status}
	var route_discount := float(job.get("discount", 1.0))
	if route_discount <= 0.0:
		route_discount = Game.BLUEPRINT_DISCOUNT if g._engine._blueprints.has(item_id) else 1.0
	var available_steps := mini(g._engine._stage_ops(),
		int(floor(minf(elapsed, Game.OFFLINE_CAP_SEC) / g._engine._brew_time())))
	if available_steps <= 0:
		return {}
	var total_estimate := int(job.get("total_estimate", plan.get("total", 0)))
	var completed := int(job.get("completed", 0))
	g._engine._production_discount = route_discount
	var pause_reason := ""
	for raw_op in plan.get("ops", []):
		var op: Dictionary = raw_op
		var a := String(op.get("a", ""))
		var b := String(op.get("b", ""))
		for _i in int(op.get("n", 0)):
			if _return_craft_steps >= available_steps:
				pause_reason = "operation_cap"
				break
			var pair_block := g._engine._production_pair_block(a, b)
			if pair_block != "":
				pause_reason = pair_block
				break
			var pair_cost := g._engine._pair_cost(a, b, route_discount)
			if not g._online._has_ingredients(a, b):
				pause_reason = "ingredients"
				break
			if g._engine._available_ether() < pair_cost:
				pause_reason = "ether"
				break
			var result := g._engine._commit_brew(a, b)
			if bool(result.get("failed", true)):
				# U9 (T11): честная причина паузы — _commit_brew теперь умеет
				# fail-closed отказ по ингредиентам/эфиру, а не только по рецепту.
				var commit_reason := String(result.get("reason", ""))
				pause_reason = commit_reason if commit_reason in ["ingredients", "ether"] else "recipe"
				break
			completed += 1
			_return_craft_steps += 1
			job["completed"] = completed
			job["status"] = "running"
		if not pause_reason.is_empty():
			break
	if _return_craft_steps <= 0 and pause_reason.is_empty():
		pause_reason = "operation_cap"
	if completed >= total_estimate:
		var saved_plan: Dictionary = job.get("plan", plan)
		g._engine._record_blueprint(item_id, saved_plan)
		Analytics.track("craft_job_complete", {
			"target": item_id, "operations": total_estimate,
			"blueprint": true, "repeat": false, "offline": true,
		})
		g._engine._craft_job.clear()
		_return_craft_status = "complete"
	else:
		job["status"] = "paused_" + pause_reason
		_return_craft_status = pause_reason
	Analytics.track("craft_job_offline", {
		"target": item_id, "steps": _return_craft_steps,
		"status": _return_craft_status,
		"completed": completed, "total": total_estimate,
	})
	g._engine._production_discount = 1.0
	return {"steps": _return_craft_steps, "status": _return_craft_status}

func _grant_offline() -> void:
	# idle-классика: за время отсутствия котёл копит эфир (до капа, максимум 8 ч);
	# цифры уходят в сводку возврата, Родник докапывает (до 50 шт., если включён)
	if g._selftest or g._last_ts <= 0.0:
		return
	var now := Time.get_unix_time_from_system()
	var elapsed := now - g._last_ts
	_return_elapsed = elapsed
	var applied := _offline_gain(elapsed, g._engine._ether_rate(), g._engine.ether, g._engine._max_ether())
	_return_ether = applied
	if applied > 0:
		g._engine.ether += applied
		g._engine.status_text = "Пока тебя не было, котёл накопил +%d ⚡" % applied
		g._spirit._companion_react("offline", str(applied))
	var craft_result := _advance_craft_job_offline(elapsed)
	if not craft_result.is_empty() and int(craft_result.get("steps", 0)) > 0:
		g._engine.status_text = "Пока тебя не было, Производство продвинулся на %d шаг(а): %s." % [
			int(craft_result["steps"]), String(craft_result.get("status", ""))]
	_return_spring = 0
	_return_spring_name = ""
	if g._engine.spring_on and g._engine._mode_unlocked("spring"):
		var sg := _spring_offline_gain(elapsed)
		if sg > 0:
			_return_spring = sg
			_return_spring_name = g._online._item_name(g._engine.spring_source)
			g._engine.inventory[g._engine.spring_source] = int(g._engine.inventory.get(g._engine.spring_source, 0)) + sg
	g._last_ts = now
	_save_game()

func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {}
	var data: Dictionary = parsed
	var version := int(data.get("version", 1))
	if version < 1 or version > Game.SAVE_VERSION:
		return {}
	if not (data.get("inventory") is Dictionary):
		return {}
	if not (data.get("known_recipes") is Array):
		return {}
	# v1/v2 → v3: добавлены pending Experiment, resumable craft_job и blueprints;
	# формат игрового сейва совместим, а отсутствующие поля получают defaults.
	# Версия фиксируется после успешной валидации, чтобы не отбрасывать прогресс.
	data["version"] = Game.SAVE_VERSION
	return data

func _delete_local_save() -> void:
	for path in [g.SAVE_PATH, g.TEMP_PATH, g.BACKUP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# ---------- сводка возврата: «пока тебя не было» ----------

func _return_due() -> bool:
	return _return_elapsed >= Game.RETURN_GAP

func _build_return_popup() -> void:
	var dim := ColorRect.new()
	dim.name = "ReturnDim"
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	g.add_child(dim)
	_return_dim = dim
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.visible = false
	g.add_child(center)
	_return_popup = center
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", g._panel_style(Color(0.09, 0.13, 0.19, 0.97), 20))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(380, 0)
	card.add_child(col)
	var t := g._label("ПОКА ТЕБЯ НЕ БЫЛО…", 18)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	col.add_child(t)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_return_list = VBoxContainer.new()
	_return_list.add_theme_constant_override("separation", 6)
	_return_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_return_list)
	var close := g._small_button("К делу!", Vector2(150, 44), 1)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_close_return_popup)
	col.add_child(close)

func _open_return_popup() -> void:
	_refresh_return_popup()
	_return_dim.visible = true
	_return_popup.visible = true
	_return_open = true
	_return_shown = true
	if not g._selftest:
		Sfx.mystic()

func _close_return_popup() -> void:
	_return_dim.visible = false
	_return_popup.visible = false
	_return_open = false
	if not g._selftest:
		Sfx.click()

func _refresh_return_popup() -> void:
	if _return_list == null:
		return
	for child in _return_list.get_children():
		_return_list.remove_child(child)
		child.queue_free()
	var dim := Color(0.6, 0.68, 0.75)
	var bright := Color(0.88, 0.94, 0.96)
	var gold := Color(1.0, 0.85, 0.42)
	var add := func(text: String, size: int, col: Color) -> void:
		var lb := g._label(text, size)
		lb.add_theme_color_override("font_color", col)
		_return_list.add_child(lb)
	add.call("Тебя не было: %s." % g._retort._retort_left_text(_return_elapsed), 13, dim)
	if _return_ether > 0:
		add.call("⚡ Котёл накопил +%d эфира." % _return_ether, 14, bright)
	else:
		add.call("⚡ Котёл уже был полон.", 14, dim)
	if _return_craft_steps > 0:
		var craft_line := "• Производство в фоне: +%d шаг(а)." % _return_craft_steps
		if _return_craft_status == "complete":
			craft_line = "• Производство завершил сохранённую цепочку и записал чертёж."
		elif _return_craft_status == "ether":
			craft_line += " Пауза: эфир."
		elif _return_craft_status == "ingredients":
			craft_line += " Пауза: ингредиенты."
		elif _return_craft_status == "operation_cap":
			craft_line += " Пауза: лимит операций этапа."
		elif _return_craft_status == "recipe":
			craft_line += " Пауза: нужен рецепт."
		elif _return_craft_status == "inventory":
			craft_line += " Пауза: нет места в инвентаре."
		add.call(craft_line, 14, bright if _return_craft_status == "complete" else gold)
	elif not g._engine._craft_job.is_empty():
		add.call("• Производство ждёт продолжения: %d/%d операций." % [
			int(g._engine._craft_job.get("completed", 0)), int(g._engine._craft_job.get("total_estimate", 0))], 14, gold)
	if _return_spring > 0:
		add.call("• Родник накапал +%d «%s»." % [_return_spring, _return_spring_name], 14, bright)
	elif g._engine.spring_on:
		add.call("• Родник капал потихоньку.", 14, dim)
	else:
		add.call("• Родник выключен — включи, и он будет капать без тебя.", 14, dim)
	if g._retort._retort_any_ready():
		add.call("• Реторта готова — неси кружку!", 14, gold)
	else:
		var bc := 0
		var best := -1.0
		for i in Game.RETORT_SLOT_MAX:
			if g._retort._retort_busy(i):
				bc += 1
				var left := g._retort._retort_left(i)
				if best < 0.0 or left < best:
					best = left
		if bc > 0:
			add.call("• В реторте зреет: %d (осталось %s)." % [bc, g._retort._retort_left_text(best)], 14, bright)
		else:
			add.call("• Реторта пустует.", 14, dim)
	if g._resonance._res_balance > 0 or g._resonance._res_total > 0:
		add.call("• Эхо: %d к получению · повторов всего %d." % [g._resonance._res_balance, g._resonance._res_total], 14, bright)
	else:
		add.call("• Эхо тихо.", 14, dim)
	if g._resonance._res_desc_total > 0:
		add.call("• Из твоих открытий родилось: %d." % g._resonance._res_desc_total, 14, bright)
	if _return_world_new > 0:
		add.call("• Мир открыл %d новых веществ." % _return_world_new, 14, bright)
	elif _return_world_new == 0:
		add.call("• В мире тихо.", 14, dim)
	if g._last_rank > 0:
		if _return_rank_old > 0 and _return_rank_old != g._last_rank:
			var arrow := "▲" if g._last_rank < _return_rank_old else "▼"
			add.call("• Рейтинг #%d (был #%d) %s" % [g._last_rank, _return_rank_old, arrow], 14, gold)
		else:
			add.call("• Рейтинг #%d." % g._last_rank, 14, bright)
	var letter_left := g._riddles._letter_unsolved_count()
	if not g._riddles._letter_today.is_empty() or not g._riddles._letter_backlog.is_empty():
		if letter_left > 0:
			var lh := String(g._riddles._letter_today.get("hint", ""))
			if lh != "" and not bool(g._riddles._letter_today.get("solved", false)):
				add.call("✦ Писем ждут разгадки: %d. Сегодня: «%s»" % [letter_left, lh], 13, gold)
			else:
				add.call("✦ Писем ждут разгадки: %d." % letter_left, 13, gold)
		else:
			add.call("✦ Письма Светика: все разгаданы ✓", 13, bright)
	elif g._riddles._letter_offline:
		add.call("✦ Письма Светика: загляни, когда будет связь.", 13, dim)
	if not g._riddles._atlas_today.is_empty():
		if bool(g._riddles._atlas_today.get("solved_by_me", false)):
			add.call("• Атлас: страница разгадана ✓ (всего %d)." % g._riddles._atlas_solved_total, 13, bright)
		else:
			add.call("• Атлас: загадка дня ждёт — разгадали уже %d." % int(g._riddles._atlas_today.get("solvers", 0)), 13, gold)
	elif g._riddles._atlas_offline:
		add.call("• Атлас: загляни, когда будет связь.", 13, dim)
	var rl := g._retort._retort_hello_line()
	add.call("• Светик: %s" % (rl if rl != "" else "Светик скучал и грел котёл."), 13, dim)

func _inject_return_demo() -> void:
	_return_elapsed = 5.0 * 3600.0 + 20.0 * 60.0
	_return_ether = 150
	_return_spring = 18
	_return_spring_name = "Вода"
	g._resonance._res_balance = 7
	g._resonance._res_total = 12
	g._resonance._res_desc_total = 3
	g._resonance._res_desc = [{"name": "Туманный янтарь", "slug": "x1", "by": "Люмина", "at": ""}]
	_return_world_new = 4
	_return_rank_old = 19
	g._last_rank = 14
	g._retort._essences = {"fire": "Огонь"}
	var now := Time.get_unix_time_from_system()
	g._retort._retort_slots = [
		{"sub": "glass", "name": "Стекло", "started": now - 13.0 * 3600.0, "dur": 12.0 * 3600.0},
		{"sub": "", "name": "", "started": 0.0, "dur": 0.0},
		{"sub": "", "name": "", "started": 0.0, "dur": 0.0},
	]
	g._riddles._inject_letter_demo()
	g._riddles._inject_atlas_demo()
