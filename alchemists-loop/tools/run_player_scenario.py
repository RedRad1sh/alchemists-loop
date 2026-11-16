import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import re
import sys
import time

from run_progression_runner import ROOT, execute_runner, find_godot, progress_path_for

DEFAULT_SCENARIO = ROOT / "tools/progression_scenarios/1h-active-5h-offline-1h-active.json"

GOAL_REASONS = {"available", "ether", "ingredients", "cooldown", "not_unlocked", "mastery", "autonomy", "rank", "recipe"}


def numeric(value):
    return type(value) in (int, float) and math.isfinite(value)


def close(a, b):
    return numeric(a) and numeric(b) and math.isclose(a, b, rel_tol=1e-9, abs_tol=1e-5)


def validate_report(report):
    if not isinstance(report, dict):
        return ["report must be an object"]
    errors = []
    required = {"schema": int, "scenario": int, "seed": int, "catalog_hash": str,
                "profile": dict, "definition": dict, "segments": list, "before": dict,
                "after": dict, "delta": dict, "time": dict, "available_goals": list,
                "blocked_goals": list, "verdict": str}
    for key, kind in required.items():
        if type(report.get(key)) is not kind:
            errors.append("missing or invalid " + key)
    if errors:
        return errors
    if report["schema"] != 1 or report["scenario"] != 1 or report["verdict"] not in ("pass", "fail", "incomplete", "invalid"):
        errors.append("unsupported schema or verdict")
    for name, value in (("catalog", report["catalog_hash"]), ("profile", report["profile"].get("hash"))):
        if not re.fullmatch("[a-f0-9]{64}", str(value)):
            errors.append("invalid " + name + " hash")
    profile = report["profile"]
    if profile.get("schema") != 1 or profile.get("base") != "baseline" or not isinstance(profile.get("name"), str) or not isinstance(profile.get("resolved_overrides"), dict):
        errors.append("invalid profile identity")
    declared = report["definition"].get("segments")
    if not isinstance(declared, list) or len(declared) != len(report["segments"]) or not declared:
        return errors + ["scenario segment count differs from definition"]
    totals = {"active_seconds": 0.0, "offline_seconds": 0.0}
    previous = report["before"]
    for index, segment in enumerate(report["segments"]):
        label = "segment " + str(index)
        if not isinstance(segment, dict):
            errors.append(label + " must be an object")
            continue
        for field in ("before", "after", "delta", "clock_delta", "ledger"):
            if not isinstance(segment.get(field), dict):
                errors.append(label + " missing " + field)
        if any(not isinstance(segment.get(f), dict) for f in ("before", "after", "delta", "clock_delta", "ledger")):
            continue
        kind, duration = segment.get("kind"), segment.get("seconds")
        if kind not in ("active", "offline") or not numeric(duration) or duration < 0:
            errors.append(label + " invalid kind/duration")
            continue
        if kind != declared[index].get("kind") or not close(duration, declared[index].get("seconds")):
            errors.append(label + " differs from scenario definition")
        if segment["before"] != previous:
            errors.append(label + " snapshot chain broken")
        previous = segment["after"]
        for snap in (segment["before"], segment["after"]):
            errors.extend(validate_snapshot(snap, label))
        start, end = segment["before"].get("clock", {}), segment["after"].get("clock", {})
        for clock_kind in ("active", "offline"):
            key = clock_kind + "_seconds"
            expected = duration if clock_kind == kind else 0
            if not close(end.get(key, 0) - start.get(key, 0), expected) or not close(segment["clock_delta"].get(key, 0), expected):
                errors.append(label + " time conservation: " + key)
        if not close(end.get("now", 0) - start.get("now", 0), duration):
            errors.append(label + " timestamp conservation")
        totals[kind + "_seconds"] += duration
        for resource in ("ether", "ether_overflow", "ether_available", "gold", "known_recipe_count"):
            actual = segment["after"].get(resource, 0) - segment["before"].get(resource, 0)
            if not close(segment["delta"].get(resource, 0), actual):
                errors.append(label + " inconsistent delta: " + resource)
        ledger = segment["ledger"]
        if ledger.get("unexplained_resources") != []:
            errors.append(label + " unexplained resources")
        events = ledger.get("events")
        if not isinstance(events, list):
            errors.append(label + " missing ledger events")
            continue
        inventory, essences, ether = {}, {}, 0
        for event in events:
            if not isinstance(event, dict) or not isinstance(event.get("deltas"), dict):
                errors.append(label + " invalid ledger transaction")
                continue
            if event.get("kind") in ("direct_grant", "grant", "base_add"):
                errors.append(label + " forbidden grant")
            delta = event["deltas"]
            ether += delta.get("ether", 0) + delta.get("reserve", 0)
            for field, target in (("inventory", inventory), ("essences", essences)):
                for item, amount in delta.get(field, {}).items():
                    target[item] = target.get(item, 0) + amount
        if not close(ether, segment["after"].get("ether_available", 0) - segment["before"].get("ether_available", 0)):
            errors.append(label + " ledger ether mismatch")
        for field, target in (("inventory", inventory), ("essences", essences)):
            before = segment["before"].get("inventory", {}) if field == "inventory" else segment["before"].get("retort", {}).get("essences", {})
            after = segment["after"].get("inventory", {}) if field == "inventory" else segment["after"].get("retort", {}).get("essences", {})
            expected = {k: after.get(k, 0) - before.get(k, 0) for k in before.keys() | after.keys()}
            if {k: v for k, v in target.items() if v} != {k: v for k, v in expected.items() if v}:
                errors.append(label + " ledger " + field + " mismatch")
            if field == "inventory" and {k: v for k, v in segment["delta"].get(field, {}).items() if v} != {k: v for k, v in expected.items() if v}:
                errors.append(label + " inventory delta mismatch")
        if kind == "offline" and report["verdict"] == "pass" and segment.get("production", {}).get("saved") is not True and duration > 0:
            errors.append(label + " offline checkpoint missing")
    if previous != report["after"]:
        errors.append("final snapshot differs from final segment")
    for key, total in totals.items():
        if not close(report["time"].get(key), total):
            errors.append("time total differs: " + key)
    if not close(report["time"].get("simulated_real_seconds"), sum(totals.values())):
        errors.append("total simulated time differs")
    if report["verdict"] == "pass" and report.get("errors"):
        errors.append("false pass with errors")
    for goal in report["available_goals"] + report["blocked_goals"]:
        if not isinstance(goal, dict) or type(goal.get("available")) is not bool or not isinstance(goal.get("missing"), dict) or not goal.get("reason"):
            errors.append("invalid goal")
        elif goal.get("reason") not in GOAL_REASONS:
            errors.append("goal reason outside vocabulary: " + str(goal.get("reason")))
    return errors


def validate_snapshot(snapshot, label):
    errors = []
    for key in ("inventory", "upgrade_levels", "workshop", "retort", "sigils", "clock"):
        if not isinstance(snapshot.get(key), dict):
            errors.append(label + " invalid snapshot." + key)
    for key in ("ether", "ether_overflow", "ether_available", "ether_cap", "gold", "known_recipe_count", "local_discovered_count"):
        if not numeric(snapshot.get(key)) or snapshot[key] < 0:
            errors.append(label + " negative or missing " + key)
    for balances in (snapshot.get("inventory", {}), snapshot.get("retort", {}).get("essences", {})):
        if any(not numeric(n) or n < 0 for n in balances.values()):
            errors.append(label + " negative or invalid resource balance")
    if not isinstance(snapshot.get("local_discovered_ids"), list) or snapshot.get("local_discovered_count") != len(snapshot.get("local_discovered_ids", [])):
        errors.append(label + " invalid discovery count")
    return errors


def build_command(scenario, profile, seed, report, godot=None):
    report = Path(report).resolve()
    return [find_godot(godot), "--headless", "--path", str(ROOT),
            "res://tests/progression_runner.tscn", "--", "--selftest",
            "--scenario=" + str(Path(scenario).resolve()), "--profile=" + str(Path(profile).resolve()),
            "--seed=" + str(seed), "--report=" + str(report), "--progress=" + str(progress_path_for(report))]


def run_profile(profile, seed, scenario, report, godot=None, timeout=120):
    report = Path(report).resolve()
    report.parent.mkdir(parents=True, exist_ok=True)
    definition = json.loads(Path(scenario).read_text(encoding="utf-8"))
    expected = json.loads(Path(profile).read_text(encoding="utf-8"))
    def validate(data):
        errors = validate_report(data)
        actual = data.get("definition", {}).get("segments", [])
        if actual != definition.get("segments"):
            errors.append("report scenario differs from invocation")
        return errors
    return execute_runner(build_command(scenario, profile, seed, report, godot), report,
                          progress_path_for(report).parent, timeout, seed, expected, validate)


def fingerprint(report):
    stable = {k: report.get(k) for k in ("seed", "catalog_hash", "profile", "definition", "before", "after", "delta", "segments", "available_goals", "verdict")}
    return hashlib.sha256(json.dumps(stable, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


def report_metrics(report):
    segments = report.get("segments", [])
    origin = report.get("before", {}).get("clock", {}).get("now", 0)
    unlocks, upgrades = {}, {}
    board_materials, board_buffs, board_decor = {}, {}, {}
    achievement_cap_delta = 0
    achievement_regen_delta = 0.0
    contract_cap_delta = 0
    contract_regen_delta = 0.0

    def add_materials(target, values):
        if not isinstance(values, dict):
            return
        for item, amount in values.items():
            target[str(item)] = target.get(str(item), 0) + amount

    def add_one(target, value):
        value = str(value or "")
        if value:
            target[value] = target.get(value, 0) + 1

    for segment in segments:
        segment_materials, segment_buffs, segment_decor = {}, {}, {}
        ledger_board_seen = False
        for event in segment.get("events", []):
            if not isinstance(event, dict):
                continue
            at = event.get("at", origin) - origin
            if event.get("kind") == "discovery":
                unlocks.setdefault(event.get("output", ""), at)
            elif event.get("kind") == "upgrade":
                upgrades.setdefault(event.get("upgrade", ""), at)
            if event.get("kind") == "contract_claim":
                add_materials(segment_materials, event.get("materials", {}))
                add_one(segment_buffs, event.get("buff", ""))
                add_one(segment_decor, event.get("decor", ""))
        for event in segment.get("ledger", {}).get("events", []):
            if not isinstance(event, dict):
                continue
            if str(event.get("kind", "")).startswith("contract_claim:") and "board_materials" in event:
                ledger_board_seen = True
                add_materials(board_materials, event.get("board_materials", {}))
                add_one(board_buffs, event.get("board_buff", ""))
                add_one(board_decor, event.get("board_decor", ""))
            achievement_cap_delta += event.get("achievement_cap_delta", 0)
            achievement_regen_delta += event.get("achievement_regen_delta", 0.0)
            contract_cap_delta += event.get("contract_cap_delta", 0)
            contract_regen_delta += event.get("contract_regen_delta", 0.0)
        if not ledger_board_seen:
            add_materials(board_materials, segment_materials)
            for buff, count in segment_buffs.items():
                board_buffs[buff] = board_buffs.get(buff, 0) + count
            for decor, count in segment_decor.items():
                board_decor[decor] = board_decor.get(decor, 0) + count

    counters = report.get("session", {}).get("counters", {})
    before = report.get("before", {})
    after = report.get("after", {})
    return {"profile": report.get("profile", {}).get("name", ""),
            "local_elements": after.get("local_discovered_count", 0),
            "new_elements": len(set(after.get("local_discovered_ids", [])) - set(before.get("local_discovered_ids", []))),
            "ether_available": after.get("ether_available", 0),
            "upgrade_purchases": counters.get("upgrade_purchases", 0),
            "player_action_seconds": counters.get("player_action_seconds", 0.0),
            "active_simulated_seconds": counters.get("active_simulated_seconds", 0.0),
            "contract_claims": counters.get("contract_claims", 0),
            "achievement_updates": counters.get("achievement_updates", 0),
            "ether_cap_delta": after.get("ether_cap", 0) - before.get("ether_cap", 0),
            "achievement_cap_delta": achievement_cap_delta,
            "achievement_regen_delta": achievement_regen_delta,
            "contract_cap_delta": contract_cap_delta,
            "contract_regen_delta": contract_regen_delta,
            "board_materials": board_materials,
            "board_buffs": board_buffs,
            "board_decor": board_decor,
            "offline_ether_earned": sum(s.get("offline_granted", {}).get("ether", 0) for s in segments),
            "offline_ether_spent": sum(s.get("offline_spent", {}).get("ether", 0) for s in segments),
            "offline_spring_items": sum(s.get("offline_granted", {}).get("spring_items", 0) for s in segments),
            "first_unlock_seconds": unlocks, "first_upgrade_seconds": upgrades,
            "blockers": report.get("blocked_goals", []), "final_delta": report.get("delta", {}),
            "segments": [{"kind": s.get("kind"), "delta": s.get("delta", {}), "offline_granted": s.get("offline_granted", {})} for s in segments]}


def compare_reports(reports):
    metrics = [report_metrics(report) for report in reports]
    for row in metrics:
        row["vs_first"] = {k: row[k] - metrics[0][k] for k in ("local_elements", "new_elements", "ether_available", "upgrade_purchases", "offline_ether_earned")}
    return {"schema": 1, "comparison": 1, "reports": reports, "metrics": metrics,
            "verdict": "pass" if reports and all(r.get("verdict") == "pass" for r in reports) else "incomplete"}


def run_profiles(profiles, seed, scenario, out, godot=None, timeout=120):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    reports, status = [], 0
    for index, profile in enumerate(profiles):
        report_path = out / (f"{index + 1:02d}-" + Path(profile).stem + ".json")
        code = run_profile(profile, seed, scenario, report_path, godot, timeout)
        status = status or code
        try:
            data = json.loads(report_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            data = {"verdict": "fail", "reason": "missing_report", "profile": {"name": Path(profile).stem}}
        data["validation_errors"] = validate_report(data)
        if code or data["validation_errors"]:
            data["verdict"] = "incomplete" if data.get("verdict") == "incomplete" else "fail"
        reports.append(data)
    comparison = compare_reports(reports)
    (out / "comparison.json").write_text(json.dumps(comparison, ensure_ascii=False, indent=2), encoding="utf-8")
    from render_progression_report import write_report
    write_report(out / "comparison.html", comparison)
    return status or (0 if comparison["verdict"] == "pass" else 2)


def main():
    parser = argparse.ArgumentParser(description="Accelerated active/offline player balance scenarios")
    parser.add_argument("--scenario", type=Path, default=DEFAULT_SCENARIO)
    parser.add_argument("--profiles", default="baseline,fast,slow")
    parser.add_argument("--profile", action="append", type=Path, help="Custom profile JSON; repeat to append several")
    parser.add_argument("--seed", type=int, default=31)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--godot")
    parser.add_argument("--timeout", type=float, default=120)
    args = parser.parse_args()
    profiles = [ROOT / "tools/balance_profiles" / (name.strip() + ".json") for name in args.profiles.split(",") if name.strip()]
    profiles.extend(args.profile or [])
    if not profiles:
        parser.error("choose at least one profile")
    out = args.out or ROOT / ".godot/acceptance/player-scenario" / str(time.time_ns())
    try:
        status = run_profiles(profiles, args.seed, args.scenario, out, args.godot, args.timeout)
    except (OSError, ValueError, TypeError) as error:
        print(str(error), file=sys.stderr)
        return 2
    print(str((out / "comparison.html").resolve()))
    return status


if __name__ == "__main__":
    sys.exit(main())
