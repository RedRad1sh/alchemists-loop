extends RefCounted

static func run(g: Game) -> void:
	var total := Selftest._total
	var failures := Selftest._fails
	var harness: Script = load("res://tests/workshop_acceptance.gd")
	Selftest.check("acceptance bounded real-flow measurement API exists", harness != null and harness.has_method("acceptance_flow"))
	if harness == null or not harness.has_method("acceptance_flow"):
		return
	var result: Dictionary = harness.acceptance_flow(g)
	for key in ["person_committed", "mastery_from_commits", "materials_produced", "exact_rank_purchase",
		"duplicate_purchase_no_debit", "two_real_lines", "safe_snapshot", "reload_offline_output",
		"reload_no_duplicate", "prestige_keeps_equipment", "prestige_clears_routes",
		"unknown_post_prestige_rejected", "known_post_prestige_production", "network_quiet", "fixture_restored"]:
		Selftest.check("acceptance actual end-to-end " + key, result.get(key, false) == true)
	Selftest.check("acceptance flow has bounded real operations", result.get("operations", 0) > 0 and result.get("operations", 10001) <= harness.OPERATION_LIMIT)
	Selftest.check("acceptance flow reports real gross debit separately", result.get("gross_ether_spent", 0) > 0
		and result.get("reward_ether", -1) >= 0 and result.get("mastery_material_preparation", 0) > 0)
	Selftest.check("acceptance UserData and telemetry already use ST paths", UserData.SAVE_PATH == UserData.ST_SAVE_PATH
		and Analytics.QUEUE_PATH == Analytics.ST_QUEUE_PATH)
	print("WORKSHOP_ACCEPTANCE_CHECKS: %d/%d" % [Selftest._total - total - (Selftest._fails - failures), Selftest._total - total])
