extends RefCounted
class_name ProgressionReport

const SCHEMA := 1


static func make(seed_value: int, profile: BalanceProfile, catalog_hash: String, clock: ProgressionClock, ledger: ProgressionLedger, phases: Dictionary, verdict: String) -> Dictionary:
	var meta := profile.metadata()
	return {"schema": SCHEMA, "seed": seed_value, "catalog_hash": catalog_hash,
		"runner_commit": "working-tree", "profile": meta,
		"profile_name": meta.get("name", ""), "profile_schema": meta.get("schema", 0),
		"base_profile": meta.get("base", ""), "profile_hash": meta.get("hash", ""),
		"resolved_overrides": meta.get("resolved_overrides", {}),
		"time": clock.snapshot(), "ledger": ledger.report(),
		"phases": phases.duplicate(true), "verdict": verdict}


static func write_atomic(path: String, report: Dictionary) -> bool:
	var target := ProjectSettings.globalize_path(path)
	var dir := target.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return false
	var temp := target + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(report, "\t"))
	file.flush()
	var stored := file.get_error() == OK
	file.close()
	# Rename in the same directory replaces the destination without an unlink gap.
	# A failed write/rename must leave the last published snapshot intact.
	if stored and DirAccess.rename_absolute(temp, target) == OK:
		return true
	DirAccess.remove_absolute(temp)
	return false
