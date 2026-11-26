extends RefCounted
class_name SuiteBalanceConfig


static func run(g: Game) -> void:
	Selftest.check("balance rejects zero brew and indexed retort durations",
		not BalanceConfig.validate_overrides({"brew.base_seconds": 0.0}).is_empty()
		and not BalanceConfig.validate_overrides({"brew.minimum_seconds": 0.0}).is_empty()
		and not BalanceConfig.validate_overrides({"retort.speed_factor.0": 0.0}).is_empty())
	var migration_profile := g.balance
	var legacy_bonus := g._retort._legacy_cap_bonus
	var essence_stock := g._retort._essence_inv.duplicate(true)
	var essence_codex := g._retort._essence_codex.duplicate(true)
	g.balance = BalanceConfig.resolve({"retort.legacy_cap_each": 17, "retort.legacy_cap_first": 1})
	g._retort.migrate_legacy_essences({"fire": "fire", "water": "water"})
	Selftest.check("balance legacy cap migration consumes active profile", g._retort._legacy_cap_bonus == 17)
	g._retort._legacy_cap_bonus = legacy_bonus
	g._retort._essence_inv = essence_stock
	g._retort._essence_codex = essence_codex
	g.balance = migration_profile
	Selftest.check("balance rejects changes to planning safety gates",
		not BalanceConfig.validate_overrides({"caps.craft_plan_hard_limit_operations": 1000}).is_empty())
	var passive_profile := g.balance
	var passive_ach := g._progress_ui._ach_done.duplicate(true)
	var passive_quests := g._guild._quests_done.duplicate(true)
	g.balance = BalanceConfig.resolve({"progression.achievement_cap": 7, "progression.achievement_regen": 0.2,
		"progression.quest_cap": 9, "progression.quest_regen": 0.4})
	if g.balance != null:
		g._progress_ui._ach_done = {"one": true}
		g._guild._quests_done = {"one": true}
	Selftest.check("balance permanent achievement and quest bonuses consume active profile", g.balance != null
		and g._progress_ui._ach_cap_bonus() == 7 and g._progress_ui._ach_regen_bonus() == 0.2
		and g._progress_ui._quest_cap_bonus() == 9 and g._progress_ui._quest_regen_bonus() == 0.4)
	g.balance = passive_profile
	g._progress_ui._ach_done = passive_ach
	g._guild._quests_done = passive_quests
	var base: BalanceProfile = BalanceConfig.baseline()
	Selftest.check("balance_config: baseline profile exists", base != null)
	if base == null:
		return

	# --- 1. Metadata & hash determinism ---
	var meta: Dictionary = base.metadata()
	Selftest.check("balance_config: metadata carries schema, name=baseline, base=baseline, empty overrides, non-empty hash",
		int(meta.get("schema", 0)) == BalanceConfig.SCHEMA_VERSION
		and String(meta.get("name", "")) == "baseline"
		and String(meta.get("base", "")) == "baseline"
		and (meta.get("resolved_overrides", null) is Dictionary)
		and (meta.get("resolved_overrides", {}) as Dictionary).is_empty()
		and String(meta.get("hash", "")).length() == 64)
	var h1: String = BalanceConfig.profile_hash(base)
	var h2: String = BalanceConfig.profile_hash(BalanceConfig.baseline())
	Selftest.check("balance_config: baseline profile_hash is deterministic across fresh instances",
		h1.length() == 64 and h1 == h2 and h1 == String(meta.get("hash", "")))
	var personal_balance: Dictionary = base.section("personal_experiment")
	Selftest.check("balance_config: personal experiment keeps success-only no-reagent invariants",
		bool(personal_balance.get("enabled", false))
		and bool(personal_balance.get("success_only_ether", false))
		and not bool(personal_balance.get("consume_reagents", true))
		and int(personal_balance.get("cost", -1)) == 12
		and is_equal_approx(float(personal_balance.get("world_target_share", -1.0)), 0.8)
		and is_equal_approx(float(personal_balance.get("llm_target_share", -1.0)), 0.2)
		and is_equal_approx(float(personal_balance.get("frontier_empty_llm_share", -1.0)), 1.0))

	# --- 2. Full parity with existing balance facades ---
	# Ether & brew
	Selftest.check("balance_config parity: ether core scalars",
		int(base.get_value("ether.brew_cost", -1)) == Balance.BREW_COST
		and int(base.get_value("ether.failure_refund", -1)) == Balance.FAILURE_REFUND
		and is_equal_approx(float(base.get_value("ether.base_regen", -1.0)), Balance.BASE_ETHER_REGEN)
		and int(base.get_value("ether.max_ether", -1)) == Balance.MAX_ETHER
		and int(base.get_value("ether.start_ether", -1)) == Balance.START_ETHER
		and int(base.get_value("ether.mastery_base", -1)) == Balance.ETHER_MASTERY_BASE
		and is_equal_approx(float(base.get_value("ether.mastery_growth", -1.0)), Balance.ETHER_MASTERY_GROWTH)
		and int(base.get_value("ether.hint_cost", -1)) == Balance.HINT_COST
		and int(base.get_value("ether.spend_guard_msec", -1)) == Balance.SPEND_GUARD_MSEC)

	# Discovery & craft planning
	var fees_ok := true
	for depth_k in Balance.DISCOVERY_FEES:
		var got_fee: int = int(base.get_value("discovery.fees.%s" % str(depth_k), -1))
		if got_fee != int(Balance.DISCOVERY_FEES[depth_k]):
			fees_ok = false
	var disc_fees: Variant = base.get_value("discovery.fees", {})
	Selftest.check("balance_config parity: discovery fees and experiment scalars",
		fees_ok and (disc_fees is Dictionary) and (disc_fees as Dictionary).size() == Balance.DISCOVERY_FEES.size()
		and int(base.get_value("discovery.arity_min", -1)) == Balance.EXPERIMENT_ARITY_MIN
		and int(base.get_value("discovery.arity_max", -1)) == Balance.EXPERIMENT_ARITY_MAX
		and is_equal_approx(float(base.get_value("discovery.cooldown_sec", -1.0)), Balance.EXPERIMENT_COOLDOWN_SEC)
		and int(base.get_value("discovery.daily_limit", -1)) == Balance.EXPERIMENT_DAILY_LIMIT
		and int(base.get_value("discovery.cost", -1)) == Balance.EXPERIMENT_COST
		and is_equal_approx(float(base.get_value("discovery.candidate_chance", -1.0)), Balance.CANDIDATE_CHANCE)
		and is_equal_approx(float(base.get_value("discovery.candidate_cooldown", -1.0)), Balance.CANDIDATE_COOLDOWN))

	# Upgrades table
	var upg: Variant = base.get_value("upgrades.items", [])
	var upg_ok: bool = (upg is Array) and (upg as Array).size() == Balance.UPGRADES.size()
	if upg_ok:
		for i in range(Balance.UPGRADES.size()):
			var src_u: Dictionary = Balance.UPGRADES[i]
			var got_u: Dictionary = (upg as Array)[i]
			if String(got_u.get("id", "")) != String(src_u["id"]) \
					or int(got_u.get("base", -1)) != int(src_u["base"]) \
					or not is_equal_approx(float(got_u.get("growth", -1.0)), float(src_u["growth"])) \
					or int(got_u.get("max", -1)) != int(src_u["max"]) \
					or String(got_u.get("unlock", "")) != String(src_u["unlock"]):
				upg_ok = false
	Selftest.check("balance_config parity: Balance.UPGRADES full table", upg_ok)

	# Offline, bench, events, sync, caps, milestones, meta
	Selftest.check("balance_config parity: offline, bench, events, sync, caps",
		is_equal_approx(float(base.get_value("offline.min_sec", -1.0)), Balance.OFFLINE_MIN_SEC)
		and is_equal_approx(float(base.get_value("offline.cap_sec", -1.0)), Balance.OFFLINE_CAP_SEC)
		and is_equal_approx(float(base.get_value("offline.return_gap_sec", -1.0)), Balance.RETURN_GAP)
		and is_equal_approx(float(base.get_value("events.bench_interval", -1.0)), Balance.BENCH_INTERVAL)
		and is_equal_approx(float(base.get_value("events.bench_offline_factor", -1.0)), Balance.BENCH_OFFLINE_FACTOR)
		and int(base.get_value("events.bench_offline_max_ticks", -1)) == Balance.BENCH_OFFLINE_MAX_TICKS
		and is_equal_approx(float(base.get_value("events.gift_interval", -1.0)), Balance.GIFT_INTERVAL)
		and is_equal_approx(float(base.get_value("events.event_interval", -1.0)), Balance.EVENT_INTERVAL)
		and is_equal_approx(float(base.get_value("events.event_window", -1.0)), Balance.EVENT_WINDOW)
		and int(base.get_value("sync.schema_version", -1)) == Balance.SYNC_SCHEMA_VERSION
		and is_equal_approx(float(base.get_value("sync.max_accrual_rate_per_sec", -1.0)), Balance.MAX_ACCRUAL_RATE_PER_SEC)
		and is_equal_approx(float(base.get_value("sync.throttle_sec", -1.0)), Balance.SYNC_THROTTLE_SEC)
		and int(base.get_value("caps.craft_inventory_stack_cap", -1)) == Balance.CRAFT_INVENTORY_STACK_CAP
		and int(base.get_value("caps.craft_stage_operations", -1)) == Balance.CRAFT_STAGE_OPERATIONS
		and int(base.get_value("caps.craft_plan_warning_operations", -1)) == Balance.CRAFT_PLAN_WARNING_OPERATIONS
		and int(base.get_value("caps.craft_plan_hard_limit_operations", -1)) == Balance.CRAFT_PLAN_HARD_LIMIT_OPERATIONS
		and is_equal_approx(float(base.get_value("brew.blueprint_discount", -1.0)), Balance.BLUEPRINT_DISCOUNT)
		and int(base.get_value("brew.guild_all_bonus", -1)) == Balance.GUILD_ALL_BONUS
		and int(base.get_value("events.challenge_reward", -1)) == Balance.CHALLENGE_REWARD)

	# Mastery & prestige
	Selftest.check("balance_config parity: mastery and prestige",
		_eq_val(base.get_value("mastery.stage_ranks", []), Balance.MASTERY_STAGE_RANKS)
		and is_equal_approx(float(base.get_value("mastery.retort_speed", -1.0)), Balance.MASTERY_RETORT_SPEED)
		and is_equal_approx(float(base.get_value("mastery.retort_min_hours", -1.0)), Balance.MASTERY_RETORT_MIN_HOURS)
		and int(base.get_value("prestige.min_items", -1)) == Balance.PRESTIGE_MIN
		and int(base.get_value("prestige.spring_keep_level", -1)) == SpringBalance.PRESTIGE_KEEP_LEVEL)

	# Milestones & retention tables from Balance
	var mile_rewards_ok := true
	for mk in Balance.MILESTONE_REWARDS:
		if int(base.get_value("milestones.rewards.%s" % str(mk), -1)) != int(Balance.MILESTONE_REWARDS[mk]):
			mile_rewards_ok = false
	Selftest.check("balance_config parity: milestones, resonance, letters, atlas, circle, vein, fair",
		_eq_val(base.get_value("milestones.thresholds", []), Balance.MILESTONES)
		and mile_rewards_ok
		and _eq_val(base.get_value("resonance.miles", []), Balance.RES_MILES)
		and is_equal_approx(float(base.get_value("resonance.regen10", -1.0)), Balance.RES_REGEN10)
		and int(base.get_value("resonance.cap50", -1)) == Balance.RES_CAP50
		and int(base.get_value("resonance.claim_gate_msec", -1)) == Balance.RESONANCE_CLAIM_GATE_MSEC
		and int(base.get_value("letters.mile_every", -1)) == Balance.LETTER_MILE_EVERY
		and int(base.get_value("letters.cap_each", -1)) == Balance.LETTER_CAP_EACH
		and int(base.get_value("letters.pending_max", -1)) == Balance.LETTER_PENDING_MAX
		and int(base.get_value("atlas.mile_every", -1)) == Balance.ATLAS_MILE_EVERY
		and int(base.get_value("atlas.cap_each", -1)) == Balance.ATLAS_CAP_EACH
		and int(base.get_value("atlas.pending_max", -1)) == Balance.ATLAS_PENDING_MAX
		and _eq_val(base.get_value("circle.day_miles", []), Balance.CIRCLE_DAY_MILES)
		and _eq_val(base.get_value("circle.pts_miles", []), Balance.CIRCLE_PTS_MILES)
		and int(base.get_value("vein.streak_cap", -1)) == Balance.VEIN_STREAK_CAP
		and int(base.get_value("vein.streak_reward", -1)) == Balance.VEIN_STREAK_REWARD
		and int(base.get_value("vein.points_world", -1)) == Balance.VEIN_POINTS_WORLD
		and is_equal_approx(float(base.get_value("fair.regen_each", -1.0)), Balance.FAIR_REGEN_EACH)
		and is_equal_approx(float(base.get_value("fair.regen_cap", -1.0)), Balance.FAIR_REGEN_CAP)
		and int(base.get_value("fair.offline_goal", -1)) == Balance.FAIR_OFFLINE_GOAL
		and is_equal_approx(float(base.get_value("fair.offline_factor", -1.0)), Balance.FAIR_OFFLINE_FACTOR))

	# Spring full tables
	Selftest.check("balance_config parity: SpringBalance full tables",
		int(base.get_value("spring.version", -1)) == SpringBalance.VERSION
		and is_equal_approx(float(base.get_value("spring.base_interval", -1.0)), Balance.SPRING_INTERVAL)
		and is_equal_approx(float(base.get_value("spring.min_interval", -1.0)), SpringBalance.MIN_INTERVAL)
		and is_equal_approx(float(base.get_value("spring.speed_factor", -1.0)), SpringBalance.SPEED_FACTOR)
		and _eq_val(base.get_value("spring.speed", []), SpringBalance.SPEED)
		and _eq_val(base.get_value("spring.volume", []), SpringBalance.VOLUME)
		and _eq_val(base.get_value("spring.volume_cap", []), SpringBalance.VOLUME_CAP)
		and _eq_val(base.get_value("spring.sources", []), SpringBalance.SOURCES)
		and _eq_val(base.get_value("spring.offline", []), SpringBalance.OFFLINE)
		and _eq_val(base.get_value("spring.offline_window_sec", []), SpringBalance.OFFLINE_WINDOW_SEC)
		and _eq_val(base.get_value("spring.material_tier", {}), SpringBalance.MATERIAL_TIER))

	# Workshop full tables
	Selftest.check("balance_config parity: WorkshopBalance full tables",
		int(base.get_value("workshop.version", -1)) == WorkshopBalance.VERSION
		and int(base.get_value("workshop.max_xp", -1)) == WorkshopBalance.MAX_XP
		and _eq_val(base.get_value("workshop.ranks", []), WorkshopBalance.RANKS)
		and _eq_val(base.get_value("workshop.autonomy", []), WorkshopBalance.AUTONOMY)
		and _eq_val(base.get_value("workshop.statuses", []), WorkshopBalance.STATUSES))

	# Retort + essences sinks full tables
	Selftest.check("balance_config parity: RetortBalance + essences full tables",
		is_equal_approx(float(base.get_value("retort.base_hours", -1.0)), Balance.RETORT_BASE_HOURS)
		and int(base.get_value("retort.slot_max", -1)) == Balance.RETORT_SLOT_MAX
		and int(base.get_value("retort.legacy_cap_each", -1)) == Balance.RETORT_CAP_EACH
		and int(base.get_value("retort.legacy_cap_first", -1)) == Balance.RETORT_CAP_FIRST
		and _eq_val(base.get_value("retort.queue_depth", []), RetortBalance.QUEUE_DEPTH)
		and _eq_val(base.get_value("retort.offline_window_sec", []), RetortBalance.OFFLINE_WINDOW_SEC)
		and _eq_val(base.get_value("retort.speed_factor", []), RetortBalance.SPEED_FACTOR)
		and _eq_val(base.get_value("retort.complexity_max_tier", []), RetortBalance.COMPLEXITY_MAX_TIER)
		and _eq_val(base.get_value("retort.queue", []), RetortBalance.QUEUE)
		and _eq_val(base.get_value("retort.offline", []), RetortBalance.OFFLINE)
		and _eq_val(base.get_value("retort.slots", []), RetortBalance.SLOTS)
		and _eq_val(base.get_value("retort.speed", []), RetortBalance.SPEED)
		and _eq_val(base.get_value("retort.complexity", []), RetortBalance.COMPLEXITY)
		and _eq_val(base.get_value("essences.blend", []), RetortBalance.BLEND)
		and _eq_val(base.get_value("essences.cap", []), RetortBalance.CAP)
		and _eq_val(base.get_value("essences.equip", []), RetortBalance.EQUIP)
		and _eq_val(base.get_value("essences.blend_recipes", {}), RetortBalance.BLEND_RECIPES))

	# Sigils card bonuses
	Selftest.check("balance_config parity: SigilManager card bonus tables",
		_eq_val(base.get_value("sigils.card_speed_pct", {}), SigilManager.CARD_SPEED_PCT)
		and _eq_val(base.get_value("sigils.card_cap", {}), SigilManager.CARD_CAP)
		and _eq_val(base.get_value("sigils.card_autonomy", {}), SigilManager.CARD_AUTONOMY)
		and is_equal_approx(float(base.get_value("sigils.chroma_speed_share", -1.0)), SigilManager.CHROMA_SPEED_SHARE))

	# --- 3. Immutability / deep-copy isolation ---
	var sec_a: Dictionary = base.section("ether")
	sec_a["brew_cost"] = 999999
	var spring_arr: Variant = base.get_value("spring.speed", [])
	if spring_arr is Array and (spring_arr as Array).size() > 0:
		((spring_arr as Array)[0] as Dictionary)["ether"] = 888888
	Selftest.check("balance_config: mutating returned section or array does not mutate profile",
		int(base.get_value("ether.brew_cost", -1)) == Balance.BREW_COST
		and int(base.get_value("spring.speed.0.ether", -1)) == int(SpringBalance.SPEED[0]["ether"]))

	# --- 4. Valid override resolution + hash change + isolation ---
	var allowed: Dictionary = BalanceConfig.allowed_parameters()
	Selftest.check("balance_config: allowed_parameters declares calibration-safe and non-safe entries",
		allowed.has("ether.brew_cost")
		and bool((allowed["ether.brew_cost"] as Dictionary).get("calibration_safe", false))
		and allowed.has("sync.schema_version")
		and not bool((allowed["sync.schema_version"] as Dictionary).get("calibration_safe", true)))

	var errs_ok: Array[String] = BalanceConfig.validate_overrides({
		"ether.brew_cost": 15,
		"spring.speed.0.ether": 40,
		"retort.base_hours": 10.0,
	})
	var custom: BalanceProfile = BalanceConfig.resolve({
		"ether.brew_cost": 15,
		"spring.speed.0.ether": 40,
		"retort.base_hours": 10.0,
	})
	Selftest.check("balance_config: valid overrides validate clean and resolve only targeted paths",
		errs_ok.is_empty() and custom != null
		and int(custom.get_value("ether.brew_cost", -1)) == 15
		and int(custom.get_value("spring.speed.0.ether", -1)) == 40
		and is_equal_approx(float(custom.get_value("retort.base_hours", -1.0)), 10.0)
		and int(custom.get_value("ether.max_ether", -1)) == Balance.MAX_ETHER
		and int(base.get_value("ether.brew_cost", -1)) == Balance.BREW_COST)
	Selftest.check("balance_config: override changes profile_hash vs baseline",
		custom != null and BalanceConfig.profile_hash(custom) != h1
		and BalanceConfig.profile_hash(custom).length() == 64)

	# --- 5. Invalid override rejection (fail-closed) ---
	Selftest.check("balance_config: rejects unknown path",
		not BalanceConfig.validate_overrides({"ether.no_such_key": 5}).is_empty()
		and BalanceConfig.resolve({"ether.no_such_key": 5}) == null)
	Selftest.check("balance_config: rejects non-calibration-safe path",
		not BalanceConfig.validate_overrides({"sync.schema_version": 5}).is_empty()
		and BalanceConfig.resolve({"sync.schema_version": 5}) == null)
	Selftest.check("balance_config: rejects wrong types (string, bool, fractional float on int)",
		not BalanceConfig.validate_overrides({"ether.brew_cost": "12"}).is_empty()
		and not BalanceConfig.validate_overrides({"ether.brew_cost": true}).is_empty()
		and not BalanceConfig.validate_overrides({"ether.brew_cost": 12.5}).is_empty()
		and BalanceConfig.resolve({"ether.brew_cost": "12"}) == null)
	Selftest.check("balance_config: rejects NaN and INF",
		not BalanceConfig.validate_overrides({"ether.base_regen": NAN}).is_empty()
		and not BalanceConfig.validate_overrides({"ether.base_regen": INF}).is_empty()
		and not BalanceConfig.validate_overrides({"ether.base_regen": -INF}).is_empty()
		and BalanceConfig.resolve({"ether.base_regen": NAN}) == null)
	Selftest.check("balance_config: rejects negative price and out-of-range values",
		not BalanceConfig.validate_overrides({"ether.brew_cost": -1}).is_empty()
		and not BalanceConfig.validate_overrides({"ether.brew_cost": 1000000}).is_empty()
		and not BalanceConfig.validate_overrides({"spring.base_interval": 0.0}).is_empty()
		and BalanceConfig.resolve({"ether.brew_cost": -1}) == null)

	var saved_brew_seconds := g.BREW_SECONDS
	g.BREW_SECONDS = 0.05
	Selftest.check("balance_config formulas: legacy brew-time property updates the single active profile",
		is_equal_approx(float(g.balance.get_value("brew.base_seconds")), 0.05))
	g.BREW_SECONDS = saved_brew_seconds
	g.balance = base
	Selftest.check("balance_config: rejects autonomy rank gate changes and zero equipment duration",
		not BalanceConfig.validate_overrides({"workshop.autonomy.1.rank": 99}).is_empty()
		and not BalanceConfig.validate_overrides({"workshop.autonomy.1.rank": 0}).is_empty()
		and not BalanceConfig.validate_overrides({"essences.equip.1.speed": 0.0}).is_empty())

	# --- 6. Facades contain no independent numeric literals & runtime reads g.balance ---
	var facade_clean := true
	for fp in [
		"res://game/data/balance.gd",
		"res://game/data/spring_balance.gd",
		"res://game/data/workshop_balance.gd",
		"res://game/data/retort_balance.gd",
	]:
		var txt: String = FileAccess.get_file_as_string(fp)
		for raw_line in txt.split("\n"):
			var line: String = raw_line.strip_edges()
			if line.begins_with("const ") and not line.contains("BalanceConfig."):
				facade_clean = false
	Selftest.check("balance_config: legacy balance files hold no independent const literals", facade_clean)

	var saved_profile: BalanceProfile = g.balance
	var base_max: int = g._engine._max_ether()
	var base_regen: float = g._engine._ether_rate()
	var base_spring_iv: float = g._engine.spring_interval()
	var base_retort_h: float = g._retort._retort_hours_for_tier(0)
	var base_ws_stages: int = g._workshop.offline_stage_limit()
	var tuned: BalanceProfile = BalanceConfig.resolve({
		"ether.max_ether": 260,
		"ether.base_regen": 0.70,
		"ether.brew_cost": 20,
		"spring.base_interval": 9.0,
		"retort.base_hours": 12.0,
		"workshop.autonomy.0.stages": 90,
	}, "tuned-test")
	g.balance = tuned
	var tuned_ok: bool = (
		g._engine._max_ether() == base_max + (260 - Balance.MAX_ETHER)
		and is_equal_approx(g._engine._ether_rate(), base_regen + (0.70 - Balance.BASE_ETHER_REGEN))
		and is_equal_approx(g._engine.spring_interval(), base_spring_iv * (9.0 / Balance.SPRING_INTERVAL))
		and is_equal_approx(g._retort._retort_hours_for_tier(0), base_retort_h * (12.0 / Balance.RETORT_BASE_HOURS))
		and g._workshop.offline_stage_limit() == base_ws_stages + (90 - 60)
	)
	g.balance = saved_profile
	var restored_ok: bool = (
		g._engine._max_ether() == base_max
		and is_equal_approx(g._engine._ether_rate(), base_regen)
		and is_equal_approx(g._engine.spring_interval(), base_spring_iv)
		and is_equal_approx(g._retort._retort_hours_for_tier(0), base_retort_h)
		and g._workshop.offline_stage_limit() == base_ws_stages
	)
	Selftest.check("balance_config: active g.balance drives Core, Spring, Retort and Workshop without leaking",
		tuned_ok and restored_ok)

	var saved_upgrades := g._engine.upgrades.duplicate(true)
	var saved_gold := g._engine.sage_gold
	var saved_mastery := g._engine.mastery_rank
	g._engine.upgrades = {"ether_regen": 1, "ether_cap": 1, "brew_speed": 1}
	g._engine.sage_gold = 2
	g._engine.mastery_rank = 0
	var formula_profile := BalanceConfig.resolve({"ether.regen_per_upgrade": 0.7,
		"ether.cap_per_upgrade": 80, "prestige.regen_per_gold": 0.1,
		"prestige.cap_per_gold": 60, "brew.base_seconds": 2.0,
		"brew.speed_factor": 0.8, "caps.craft_stage_operations": 5,
		"retort.tier_hours_factor": 0.75, "essences.blend_base_hours": 10.0}, "formula-test")
	Selftest.check("balance_config formulas: all remaining economy scalars resolve", formula_profile != null)
	if formula_profile != null:
		g.balance = formula_profile
		Selftest.check("balance_config formulas: ether upgrades, prestige and brew time use active profile",
			is_equal_approx(g._engine._sage_multiplier(), 1.2)
			and g._engine._max_ether() >= 180 + 80 + 120
			and is_equal_approx(g._engine._brew_time(), 1.6)
			and g._engine._stage_ops() == 5
			and is_equal_approx(g._retort._retort_hours_for_tier(1), 14.0)
			and is_equal_approx(g._retort._blend_hours(), 10.0))
	g.balance = saved_profile
	g._engine.upgrades = saved_upgrades
	g._engine.sage_gold = saved_gold
	g._engine.mastery_rank = saved_mastery

	var extras := BalanceConfig.resolve({"brew.blueprint_discount": 0.5, "events.gift_interval": 10.0,
		"workshop.xp_per_synthesis_max": 3, "sigils.set_cap_bonus": 60,
		"sigils.set_craft_factor": 0.8, "sigils.set_speed_factor": 0.4,
		"milestones.regen20": 1.0, "milestones.regen57": 1.5, "milestones.cap40": 70}, "extras-test")
	Selftest.check("balance_config formulas: reward and production modifiers resolve", extras != null)
	if extras != null:
		g.balance = extras
		var saved_claimed := g._sigil._milestones_claimed.duplicate(true)
		var saved_milestones := g._engine._milestones_done.duplicate(true)
		g._sigil._milestones_claimed = {"earth": [3, 6, 13]}
		g._engine._milestones_done = {20: true, 40: true, 57: true}
		Selftest.check("balance_config formulas: sigil set and collection bonuses consume profile",
			g._sigil.milestone_cap_bonus() == 60
			and g._sigil.craft_ether_cost({"set": "earth", "ether_cost": 100}) == 80
			and is_equal_approx(g._sigil.bench_interval("brick"), 16.0)
			and is_equal_approx(g._engine._collection_regen_bonus(), 2.5)
			and g._engine._collection_cap_bonus() == 70)
		g._sigil._milestones_claimed = saved_claimed
		g._engine._milestones_done = saved_milestones
	g.balance = saved_profile

	# --- 7. External JSON profile loading & document validation (Task 4) ---
	var p_base: BalanceProfile = BalanceConfig.load_profile_json("res://tools/balance_profiles/baseline.json")
	var p_fast: BalanceProfile = BalanceConfig.load_profile_json("res://tools/balance_profiles/fast.json")
	var p_slow: BalanceProfile = BalanceConfig.load_profile_json("res://tools/balance_profiles/slow.json")
	Selftest.check("balance_config json: baseline.json resolves to typed baseline hash",
		p_base != null
		and String(p_base.metadata().get("name", "")) == "baseline"
		and BalanceConfig.profile_hash(p_base) == h1)
	Selftest.check("balance_config json: fast.json and slow.json load with distinct hashes and metadata",
		p_fast != null and p_slow != null
		and String(p_fast.metadata().get("name", "")) == "fast"
		and String(p_slow.metadata().get("name", "")) == "slow"
		and BalanceConfig.profile_hash(p_fast) != h1
		and BalanceConfig.profile_hash(p_slow) != h1
		and BalanceConfig.profile_hash(p_fast) != BalanceConfig.profile_hash(p_slow))
	Selftest.check("balance_config json: rejects missing fields, bad schema, bad base, and missing file",
		not BalanceConfig.validate_profile_document({}).is_empty()
		and not BalanceConfig.validate_profile_document({"schema": 999, "name": "x", "base": "baseline", "overrides": {}}).is_empty()
		and not BalanceConfig.validate_profile_document({"schema": 1, "name": "x", "base": "other", "overrides": {}}).is_empty()
		and not BalanceConfig.validate_profile_document({"schema": 1, "name": "", "base": "baseline", "overrides": {}}).is_empty()
		and not BalanceConfig.validate_profile_document({"schema": 1, "name": "x", "base": "baseline", "overrides": {"sync.schema_version": 5}}).is_empty()
		and BalanceConfig.load_profile_json("res://tools/balance_profiles/does_not_exist.json") == null)


static func _eq_val(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
			return is_equal_approx(float(a), float(b))
		return false
	if a is float:
		return is_equal_approx(float(a), float(b))
	if a is Array:
		var aa: Array = a
		var bb: Array = b
		if aa.size() != bb.size():
			return false
		for i in range(aa.size()):
			if not _eq_val(aa[i], bb[i]):
				return false
		return true
	if a is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return false
		for k in da:
			if not db.has(k) and not db.has(str(k)):
				return false
			var kb: Variant = k if db.has(k) else str(k)
			if not _eq_val(da[k], db[kb]):
				return false
		return true
	return a == b
