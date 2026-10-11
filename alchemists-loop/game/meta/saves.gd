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
var _return_bench_steps: int = 0
var _return_bench_items: int = 0
var _return_bench_status: String = ""
var _return_workshop: Dictionary = {}
## Зонд для selftest: разрешает прогнать офлайн-верстак напрямую, минуя
## _grant_offline (тот в selftest не вызывается вовсе).
var _saves_bench_probe: bool = false
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

var _save_frozen := false
# #8: после «Удалить локальные данные» память всё ещё держит старый прогресс,
# а _save_game() вызывается ~из ста мест (автосейв по таймеру, пауза, закрытие,
# награды). Заморозка в единственной точке записи — единственный способ
# гарантированно не пересоздать удалённый файл старым состоянием.

func _save_game() -> bool:
	if _save_frozen:
		return false
	# This is the authoritative online boundary, not a timer/frame callback.
	# Build the watermark with the resources; publish it in memory only after IO.
	var workshop_state := g._workshop.export_state()
	var snapshot_ts := maxf(_timestamp(g._last_ts), _timestamp(Time.get_unix_time_from_system()))
	snapshot_ts = maxf(snapshot_ts, _timestamp(workshop_state.get("last_simulated_at")))
	if not g._workshop.is_read_only():
		workshop_state["last_simulated_at"] = snapshot_ts
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
		"workshop": workshop_state,
		"regen_clock": _clock(g._engine.regen_clock, 1.0),
		"spring_clock": _clock(g._pages._spring_clock, Game.SPRING_INTERVAL),
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
		"last_ts": snapshot_ts,
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
		"circle_local_done_day": g._retention._circle_local_done_day,
		"week_cache": g._retention._week_cache,
		"vein_cap_total": g._retention._vein_cap_total,
		"cycle_cache": g._retention._cycle_cache,
		"vein_pending_finds": g._retention._vein_finds,
		"unlocked_titles": g._retention._unlocked_titles,
		"active_title": g._retention._active_title,
		"circle_intro_shown": g._retention._circle_intro_shown,
		"server_tags": g._online._server_tag,
		"fair_regen_total": g._retention._fair_regen_total,
		"fair_local_week": g._retention._fair_local_week,
		"fair_local_brews": g._retention._fair_local_brews,
		"fair_off_claim_week": g._retention._fair_off_claim_week
	}
	# S1 социалка: ключи social_cache/social_last_read — единый источник формы
	# (Social.to_save()); плоская сборка, как week_cache/cycle_cache выше.
	data.merge(g._social.to_save())
	var file := FileAccess.open(g.TEMP_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Не удалось открыть временный файл сохранения.")
		return false
	# Timers and Unix watermarks must round-trip the actual double, not a rounded
	# presentation number that can move the durable boundary behind the memory.
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		push_warning("Не удалось записать временный файл сохранения.")
		return false
	var save_abs := ProjectSettings.globalize_path(g.SAVE_PATH)
	var temp_abs := ProjectSettings.globalize_path(g.TEMP_PATH)
	var backup_abs := ProjectSettings.globalize_path(g.BACKUP_PATH)
	if FileAccess.file_exists(g.SAVE_PATH):
		if FileAccess.file_exists(g.BACKUP_PATH):
			if DirAccess.remove_absolute(backup_abs) != OK:
				push_warning("Не удалось обновить backup.")
				return false
		if DirAccess.rename_absolute(save_abs, backup_abs) != OK:
			push_warning("Не удалось создать backup.")
			return false
	if DirAccess.rename_absolute(temp_abs, save_abs) != OK:
		push_warning("Не удалось установить новое сохранение.")
		if FileAccess.file_exists(g.BACKUP_PATH):
			DirAccess.rename_absolute(backup_abs, save_abs)
		return false
	g._last_ts = snapshot_ts
	if not g._workshop.is_read_only():
		g._workshop.last_simulated_at = snapshot_ts
	return true

static func _clock(raw: Variant, period: float) -> float:
	if (raw is int or raw is float) and is_finite(float(raw)) and float(raw) >= 0.0 and float(raw) < period:
		return float(raw)
	return 0.0

static func _timestamp(raw: Variant) -> float:
	if (raw is int or raw is float) and is_finite(float(raw)) and float(raw) >= 0.0:
		return float(raw)
	return 0.0

func _load_game() -> void:
	var data := _read_save(g.SAVE_PATH)
	if data.is_empty():
		data = _read_save(g.BACKUP_PATH)
	if data.is_empty():
		return
	var frozen := _save_frozen
	_save_frozen = true
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
	g._online._server_layers.clear()
	if data.get("server_layers") is Dictionary:
		for k in data["server_layers"]:
			g._online._server_layers[String(k)] = g._online._validated_server_layer(data["server_layers"][k])
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
	# Тип проверяем до typed-присваивания: String в Dictionary-поле сейва
	# иначе роняет загрузку на этапе объявления переменной.
	var lcache_raw: Variant = data.get("letter_cache", {})
	var lcache: Dictionary = lcache_raw if typeof(lcache_raw) == TYPE_DICTIONARY else {}
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
	var acache_raw: Variant = data.get("atlas_cache", {})
	var acache: Dictionary = acache_raw if typeof(acache_raw) == TYPE_DICTIONARY else {}
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
	g._last_ts = _timestamp(data.get("last_ts"))
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
	g._retention._circle_local_done_day = String(data.get("circle_local_done_day", ""))
	g._retention._week_cache = data.get("week_cache", {}) if data.get("week_cache", {}) is Dictionary else {}
	g._retention._vein_cap_total = maxi(0, int(data.get("vein_cap_total", 0)))
	g._retention._cycle_cache = data.get("cycle_cache", {}) if data.get("cycle_cache", {}) is Dictionary else {}
	# S1 социалка: type-guard на старые сейвы (без ключей) — внутри from_save.
	g._social.from_save(data)
	g._retention._vein_finds.clear()
	if data.get("vein_pending_finds") is Array:
		for f in data["vein_pending_finds"]:
			if typeof(f) == TYPE_DICTIONARY and f.has("id"):
				g._retention._vein_finds.append(f)
	g._retention._unlocked_titles.clear()
	if data.get("unlocked_titles") is Array:
		for t in data["unlocked_titles"]:
			g._retention._unlocked_titles.append(String(t))
	g._retention._active_title = String(data.get("active_title", ""))
	g._retention._circle_intro_shown = bool(data.get("circle_intro_shown", false))
	# Migration: grant titles and fireplace rewards for milestones already passed
	g._retention._circle_migrate_missed_milestones()
	g._online._server_tag.clear()
	if data.get("server_tags") is Dictionary:
		for k in data["server_tags"]:
			g._online._server_tag[String(k)] = String(data["server_tags"][k])
	g._retention._fair_regen_total = clampf(float(data.get("fair_regen_total", 0.0)), 0.0, Game.FAIR_REGEN_CAP)
	g._retention._fair_local_week = String(data.get("fair_local_week", ""))
	g._retention._fair_local_brews.clear()
	if data.get("fair_local_brews") is Array:
		for b in data["fair_local_brews"]:
			g._retention._fair_local_brews.append(String(b))
	g._retention._fair_off_claim_week = String(data.get("fair_off_claim_week", ""))
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
	g._workshop.import_state(data.get("workshop"), data)
	if data.has("companion_unlocked"):
		g._spirit._companion_unlocked = bool(data["companion_unlocked"])
	else:
		# старый сейв: Светик открыт, если уже знаком или Искра уже в запасе
		g._spirit._companion_unlocked = g._spirit._companion_met or g._engine.inventory.has("spark")
	g._engine.status_text = "Лаборатория восстановлена. Продолжим эксперименты!"
	# Restore fractions only after inventory, recipes, equipment and migrations.
	g._engine.regen_clock = _clock(data.get("regen_clock"), 1.0)
	g._pages._spring_clock = _clock(data.get("spring_clock"), Game.SPRING_INTERVAL)
	_save_frozen = frozen
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

func _bench_offline_ticks(elapsed: float) -> int:
	# Compatibility estimate only; the scheduler owns real time and execution.
	if not is_finite(elapsed) or elapsed < Game.OFFLINE_MIN_SEC:
		return 0
	var eff := minf(elapsed, Game.OFFLINE_CAP_SEC)
	var interval: float = g._sigil.bench_interval(g._pages._bench_target)
	var ticks := int(floor(eff / interval * Game.BENCH_OFFLINE_FACTOR))
	return mini(ticks, g._workshop.offline_stage_limit())

func _advance_bench_offline(elapsed: float) -> Dictionary:
	# One explicit relative simulated window, shared with all other consumers.
	# The actual return orchestrator never chains these compatibility adapters.
	_return_bench_steps = 0
	_return_bench_items = 0
	_return_bench_status = ""
	if g._selftest and not _saves_bench_probe:
		return {}
	if not g._engine._mode_unlocked("bench"):
		return {}
	if not g._pages._bench_on or g._pages._bench_target == "":
		return {}
	if not is_finite(elapsed) or elapsed < Game.OFFLINE_MIN_SEC:
		return {}
	if not g._pages._sync_legacy_bench():
		return {}
	var queues := _workshop_queues()
	var result: Dictionary = g._workshop_scheduler.advance(elapsed, true)
	_project_workshop(result, queues)
	return {"steps": _return_bench_steps, "items": _return_bench_items, "status": _return_bench_status}

func _advance_craft_job_offline(elapsed: float) -> Dictionary:
	# Another explicit single shared window; its return projects manual work only.
	_return_craft_steps = 0
	_return_craft_status = ""
	if not is_finite(elapsed) or elapsed < Game.OFFLINE_MIN_SEC or g._engine._craft_job.is_empty():
		return {}
	var queues := _workshop_queues()
	var result: Dictionary = g._workshop_scheduler.advance(elapsed, true)
	_project_workshop(result, queues)
	return {"steps": _return_craft_steps, "status": _return_craft_status}

func _grant_offline() -> void:
	if g._selftest or g._last_ts <= 0.0:
		return
	var now := Time.get_unix_time_from_system()
	_return_elapsed = maxf(0.0, now - g._last_ts)
	var queues := _workshop_queues()
	var frozen := _save_frozen
	_save_frozen = true
	# Exactly one absolute replay includes ether, spring, manual chain and lines.
	var result: Dictionary = g._workshop_scheduler.replay_offline(g._last_ts, now)
	_project_workshop(result, queues)
	g._last_ts = maxf(_timestamp(g._last_ts), maxf(_timestamp(result.get("consumed_until")), now))
	if _return_ether > 0:
		g._spirit._companion_react("offline", str(_return_ether))
	if int(result.get("steps", 0)) > 0:
		g._engine.status_text = "Пока тебя не было: %d операций, %d целевых веществ, +%d мастерства Мастерской." % [
			int(result["steps"]), int(result["items"]), int(result["mastery"])]
	_save_frozen = frozen
	# A freeze/IO failure must not be described as durable replay progress.
	_return_workshop["saved"] = _save_game()

func _workshop_queues() -> Dictionary:
	var queues := {}
	for line in g._workshop.lines:
		queues[String(line["id"])] = line["queue"].duplicate(true)
	return queues

func _project_workshop(result: Dictionary, before_queues: Dictionary) -> void:
	_return_workshop = result.duplicate(true)
	_return_ether = int(result.get("ether_gained", 0))
	_return_spring = int(result.get("spring_items", 0))
	_return_spring_name = g._online._item_name(g._engine.spring_source) if _return_spring > 0 else ""
	_return_craft_steps = int(result.get("craft_steps", 0))
	_return_craft_status = String(result.get("craft_status", ""))
	_return_bench_steps = 0
	_return_bench_items = 0
	_return_bench_status = ""
	var after_queues := _workshop_queues()
	for id in _return_workshop.get("lines", {}):
		var info: Dictionary = _return_workshop["lines"][id]
		var remaining: Array = after_queues.get(id, [])
		info["queue_count"] = remaining.size()
		if g._workshop.is_read_only():
			info["status"] = "read_only"
		elif not g._workshop.unlocked:
			info["status"] = "locked"
		elif not remaining.is_empty():
			info["status"] = remaining[0]["status"]
			if String(info.get("reason", "")) == "": info["reason"] = remaining[0]["reason"]
		_return_bench_steps += int(info.get("steps", 0))
		_return_bench_items += int(info.get("items", 0))
		var status := String(info.get("status", "idle"))
		if status.begins_with("waiting_"):
			_return_bench_status = status.trim_prefix("waiting_")
		elif _return_bench_status == "" and status != "idle":
			_return_bench_status = status
		# The scheduler reports line totals. Job progress gives the actual target
		# breakdown, including completed/removed batches, never planned operations.
		var outputs := {}
		var targets: Array[String] = []
		var left := int(info.get("items", 0))
		for job in before_queues.get(id, []):
			var target := String(job["target"])
			if not targets.has(target): targets.append(target)
			var produced := int(job["amount"]) if job["mode"] == "batch" else int(job["produced"])
			for after in after_queues.get(id, []):
				if after["id"] == job["id"]:
					produced = int(after["produced"])
					break
			var actual := mini(left, maxi(0, produced - int(job["produced"])))
			if actual > 0: outputs[target] = int(outputs.get(target, 0)) + actual
			left -= actual
		info["outputs"] = outputs
		info["targets"] = targets
	if _return_bench_status == "" and _return_bench_steps > 0:
		_return_bench_status = "complete" # empty queues, not merely processed time

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
	_save_frozen = true
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
	dim.z_index = 20
	dim.visible = false
	g.add_child(dim)
	_return_dim = dim
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.z_index = 21
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
	if not _return_workshop.is_empty():
		add.call("⚡ Котёл добавил +%d эфира; производство потратило %d." % [
			_return_ether, int(_return_workshop.get("ether_spent", 0))], 14, bright)
		var clock_status := String(_return_workshop.get("status", "idle"))
		if clock_status == "complete":
			add.call("Мастерская: время отсутствия обработано. Состояния заданий — ниже.", 13, dim)
		elif clock_status == "idle":
			add.call("Мастерская: нового времени для обработки нет.", 13, dim)
		else:
			add.call("Мастерская: обработка времени остановилась (%s)." % clock_status, 13, gold)
		for line in _workshop_return_lines():
			add.call(line, 14, bright)
		if _return_craft_steps > 0 or _return_craft_status != "":
			add.call("• Ручная цепочка: %d операций, %d целевых выходов; состояние: %s." % [
				_return_craft_steps, int(_return_workshop.get("craft_items", 0)), _return_craft_status], 14, bright)
		if _return_workshop.has("saved") and not bool(_return_workshop["saved"]):
			add.call("Прогресс возврата в памяти; сохранение ещё не записано.", 13, gold)
	elif _return_ether > 0:
		add.call("⚡ Котёл накопил +%d эфира." % _return_ether, 14, bright)
	else:
		add.call("⚡ Котёл уже был полон.", 14, dim)
	if _return_workshop.is_empty() and _return_craft_steps > 0:
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
	elif _return_workshop.is_empty() and not g._engine._craft_job.is_empty():
		add.call("• Производство ждёт продолжения: %d/%d операций." % [
			int(g._engine._craft_job.get("completed", 0)), int(g._engine._craft_job.get("total_estimate", 0))], 14, gold)
	if not _return_workshop.is_empty():
		add.call("• Родник: +%d доставок%s." % [_return_spring,
			" «%s»" % _return_spring_name if _return_spring > 0 else ""], 14, bright if _return_spring > 0 else dim)
	elif _return_spring > 0:
		add.call("• Родник накапал +%d «%s»." % [_return_spring, _return_spring_name], 14, bright)
	elif g._engine.spring_on:
		add.call("• Родник капал потихоньку.", 14, dim)
	else:
		add.call("• Родник выключен — включи, и он будет капать без тебя.", 14, dim)
	if _return_workshop.is_empty() and (_return_bench_steps > 0 or _return_bench_status != ""):
		var bench_line := "• Верстак в фоне (вполсилы): +%d варок." % _return_bench_steps
		if _return_bench_items > 0:
			bench_line += " «%s» готов и записан в чертёж." % g._online._item_name(g._pages._bench_target)
		if _return_bench_status == "inventory":
			bench_line += " Пауза: нет места в инвентаре."
		elif _return_bench_status == "ether":
			bench_line += " Пауза: эфир."
		elif _return_bench_status == "ingredients":
			bench_line += " Пауза: ингредиенты."
		elif _return_bench_status == "recipe":
			bench_line += " Пауза: нужен рецепт."
		elif _return_bench_status == "budget":
			bench_line += " Дальше — вживую."
		add.call(bench_line, 14, bright if _return_bench_items > 0 else gold)
	elif _return_workshop.is_empty() and _return_bench_status == "" and g._pages._bench_on and g._pages._bench_target != "":
		add.call("• Верстак стоял: слишком короткое отсутствие.", 14, dim)
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

func _workshop_return_lines() -> Array[String]:
	var text: Array[String] = []
	for id in _return_workshop.get("lines", {}):
		var info: Dictionary = _return_workshop["lines"][id]
		var outputs: Array[String] = []
		for target in info.get("outputs", {}):
			outputs.append("%s ×%d" % [g._online._item_name(String(target)), int(info["outputs"][target])])
		var goals: Array[String] = []
		for target in info.get("targets", []): goals.append(g._online._item_name(String(target)))
		var status := String(info.get("status", "idle"))
		var statuses := {"idle": "нет активного задания", "running": "работает",
			"paused_user": "остановлена игроком", "waiting_ether": "ждёт эфир",
			"waiting_ingredients": "ждёт ингредиенты", "waiting_recipe": "ждёт рецепт",
			"waiting_inventory": "ожидает изменения запаса", "locked": "ещё закрыта",
			"read_only": "нужна новая версия игры"}
		var line := "• Линия %s%s: %d операций; целевой выход: %s; Мастерство Мастерской +%d; в очереди: %d. Состояние: %s." % [
			String(id), " (%s)" % ", ".join(goals) if not goals.is_empty() else "",
			int(info.get("steps", 0)), ", ".join(outputs) if not outputs.is_empty() else "0",
			int(info.get("mastery", 0)), int(info.get("queue_count", 0)), String(statuses.get(status, status))]
		var reason := String(info.get("reason", ""))
		if reason != "": line += " Причина: " + reason
		text.append(line)
	return text

func _inject_return_demo() -> void:
	_return_workshop.clear()
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
