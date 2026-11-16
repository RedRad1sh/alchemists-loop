extends RefCounted
class_name Balance
# Compatibility facade: single source of balance tables is BalanceConfig.

const SYNC_SCHEMA_VERSION: int = BalanceConfig.BASELINE_DATA["sync"]["schema_version"]
const MAX_ACCRUAL_RATE_PER_SEC: float = BalanceConfig.BASELINE_DATA["sync"]["max_accrual_rate_per_sec"]
const SYNC_THROTTLE_SEC: float = BalanceConfig.BASELINE_DATA["sync"]["throttle_sec"]

const BREW_COST: int = BalanceConfig.BASELINE_DATA["ether"]["brew_cost"]
const FAILURE_REFUND: int = BalanceConfig.BASELINE_DATA["ether"]["failure_refund"]
const BASE_ETHER_REGEN: float = BalanceConfig.BASELINE_DATA["ether"]["base_regen"]
const MAX_ETHER: int = BalanceConfig.BASELINE_DATA["ether"]["max_ether"]
const START_ETHER: int = BalanceConfig.BASELINE_DATA["ether"]["start_ether"]
const DISCOVERY_FEES: Dictionary = BalanceConfig.BASELINE_DATA["discovery"]["fees"]
const ETHER_MASTERY_BASE: int = BalanceConfig.BASELINE_DATA["ether"]["mastery_base"]
const ETHER_MASTERY_GROWTH: float = BalanceConfig.BASELINE_DATA["ether"]["mastery_growth"]

const UPGRADES: Array = BalanceConfig.BASELINE_DATA["upgrades"]["items"]
const HINT_COST: int = BalanceConfig.BASELINE_DATA["ether"]["hint_cost"]
const SPEND_GUARD_MSEC: int = BalanceConfig.BASELINE_DATA["ether"]["spend_guard_msec"]

const RES_MILES: Array = BalanceConfig.BASELINE_DATA["resonance"]["miles"]
const RES_REGEN10: float = BalanceConfig.BASELINE_DATA["resonance"]["regen10"]
const RES_CAP50: int = BalanceConfig.BASELINE_DATA["resonance"]["cap50"]
const RESONANCE_CLAIM_GATE_MSEC: int = BalanceConfig.BASELINE_DATA["resonance"]["claim_gate_msec"]

const RETORT_BASE_HOURS: float = BalanceConfig.BASELINE_DATA["retort"]["base_hours"]
const RETORT_CAP_EACH: int = BalanceConfig.BASELINE_DATA["retort"]["legacy_cap_each"]
const RETORT_CAP_FIRST: int = BalanceConfig.BASELINE_DATA["retort"]["legacy_cap_first"]

const LETTER_MILE_EVERY: int = BalanceConfig.BASELINE_DATA["letters"]["mile_every"]
const LETTER_CAP_EACH: int = BalanceConfig.BASELINE_DATA["letters"]["cap_each"]
const LETTER_PENDING_MAX: int = BalanceConfig.BASELINE_DATA["letters"]["pending_max"]

const ATLAS_MILE_EVERY: int = BalanceConfig.BASELINE_DATA["atlas"]["mile_every"]
const ATLAS_CAP_EACH: int = BalanceConfig.BASELINE_DATA["atlas"]["cap_each"]
const ATLAS_PENDING_MAX: int = BalanceConfig.BASELINE_DATA["atlas"]["pending_max"]

const HEARTH_BASE: int = BalanceConfig.BASELINE_DATA["circle"]["hearth_base"]
const CIRCLE_DAY_MILES: Array = BalanceConfig.BASELINE_DATA["circle"]["day_miles"]
const CIRCLE_DAY_CAP: Dictionary = BalanceConfig.BASELINE_DATA["circle"]["day_cap"]
const CIRCLE_DAY_REGEN: Dictionary = BalanceConfig.BASELINE_DATA["circle"]["day_regen"]
const CIRCLE_PTS_MILES: Array = BalanceConfig.BASELINE_DATA["circle"]["pts_miles"]
const CIRCLE_PTS_CAP: Dictionary = BalanceConfig.BASELINE_DATA["circle"]["pts_cap"]
const CIRCLE_PTS_REGEN: Dictionary = BalanceConfig.BASELINE_DATA["circle"]["pts_regen"]

const VEIN_STREAK_CAP: int = BalanceConfig.BASELINE_DATA["vein"]["streak_cap"]
const VEIN_STREAK_REWARD: int = BalanceConfig.BASELINE_DATA["vein"]["streak_reward"]
const VEIN_POINTS_WORLD: int = BalanceConfig.BASELINE_DATA["vein"]["points_world"]

const CIRCLE_RANKS: Array = BalanceConfig.BASELINE_DATA["circle"]["ranks"]
const CIRCLE_DECOR_REWARDS: Dictionary = BalanceConfig.BASELINE_DATA["circle"]["decor_rewards"]

const FAIR_REGEN_EACH: float = BalanceConfig.BASELINE_DATA["fair"]["regen_each"]
const FAIR_REGEN_CAP: float = BalanceConfig.BASELINE_DATA["fair"]["regen_cap"]
const FAIR_OFFLINE_GOAL: int = BalanceConfig.BASELINE_DATA["fair"]["offline_goal"]
const FAIR_OFFLINE_FACTOR: float = BalanceConfig.BASELINE_DATA["fair"]["offline_factor"]

const RETURN_GAP: float = BalanceConfig.BASELINE_DATA["offline"]["return_gap_sec"]
const SPRING_INTERVAL: float = BalanceConfig.BASELINE_DATA["spring"]["base_interval"]
const BENCH_INTERVAL: float = BalanceConfig.BASELINE_DATA["events"]["bench_interval"]
const BENCH_OFFLINE_FACTOR: float = BalanceConfig.BASELINE_DATA["events"]["bench_offline_factor"]
const BENCH_OFFLINE_MAX_TICKS: int = BalanceConfig.BASELINE_DATA["events"]["bench_offline_max_ticks"]
const GIFT_INTERVAL: float = BalanceConfig.BASELINE_DATA["events"]["gift_interval"]
const EVENT_INTERVAL: float = BalanceConfig.BASELINE_DATA["events"]["event_interval"]
const EVENT_WINDOW: float = BalanceConfig.BASELINE_DATA["events"]["event_window"]

const EXPERIMENT_ARITY_MIN: int = BalanceConfig.BASELINE_DATA["discovery"]["arity_min"]
const EXPERIMENT_ARITY_MAX: int = BalanceConfig.BASELINE_DATA["discovery"]["arity_max"]
const EXPERIMENT_COOLDOWN_SEC: float = BalanceConfig.BASELINE_DATA["discovery"]["cooldown_sec"]
const EXPERIMENT_DAILY_LIMIT: int = BalanceConfig.BASELINE_DATA["discovery"]["daily_limit"]
const EXPERIMENT_COST: int = BalanceConfig.BASELINE_DATA["discovery"]["cost"]
const EXPERIMENT_FAILURE_REFUND: int = BalanceConfig.BASELINE_DATA["discovery"]["failure_refund"]
const CRAFT_STAGE_OPERATIONS: int = BalanceConfig.BASELINE_DATA["caps"]["craft_stage_operations"]

const MASTERY_STAGE_RANKS: Array = BalanceConfig.BASELINE_DATA["mastery"]["stage_ranks"]
const MASTERY_RETORT_SPEED: float = BalanceConfig.BASELINE_DATA["mastery"]["retort_speed"]
const MASTERY_RETORT_MIN_HOURS: float = BalanceConfig.BASELINE_DATA["mastery"]["retort_min_hours"]
const RETORT_SLOT_MAX: int = BalanceConfig.BASELINE_DATA["retort"]["slot_max"]
const CRAFT_PLAN_WARNING_OPERATIONS: int = BalanceConfig.BASELINE_DATA["caps"]["craft_plan_warning_operations"]
const CRAFT_PLAN_HARD_LIMIT_OPERATIONS: int = BalanceConfig.BASELINE_DATA["caps"]["craft_plan_hard_limit_operations"]
const CRAFT_INVENTORY_STACK_CAP: int = BalanceConfig.BASELINE_DATA["caps"]["craft_inventory_stack_cap"]
const BLUEPRINT_DISCOUNT: float = BalanceConfig.BASELINE_DATA["brew"]["blueprint_discount"]
const GUILD_ALL_BONUS: int = BalanceConfig.BASELINE_DATA["brew"]["guild_all_bonus"]

const CANDIDATE_CHANCE: float = BalanceConfig.BASELINE_DATA["discovery"]["candidate_chance"]
const CANDIDATE_COOLDOWN: float = BalanceConfig.BASELINE_DATA["discovery"]["candidate_cooldown"]
const NET_NICK: String = BalanceConfig.BASELINE_DATA["caps"]["net_nick"]
const CHALLENGE_REWARD: int = BalanceConfig.BASELINE_DATA["events"]["challenge_reward"]
const WORLD_PAGE_SIZE: int = BalanceConfig.BASELINE_DATA["caps"]["world_page_size"]

const PRESTIGE_MIN: int = BalanceConfig.BASELINE_DATA["prestige"]["min_items"]
const OFFLINE_MIN_SEC: float = BalanceConfig.BASELINE_DATA["offline"]["min_sec"]
const OFFLINE_CAP_SEC: float = BalanceConfig.BASELINE_DATA["offline"]["cap_sec"]
const MILESTONES: Array = BalanceConfig.BASELINE_DATA["milestones"]["thresholds"]
const MILESTONE_REWARDS: Dictionary = BalanceConfig.BASELINE_DATA["milestones"]["rewards"]
