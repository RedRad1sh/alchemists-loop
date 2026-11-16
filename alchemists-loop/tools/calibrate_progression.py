import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import sys

from run_progression_runner import ROOT, number, run_profile, validate_report


def score(report, targets, overrides):
    metrics = report.get("metrics", {})
    elements = metrics.get("local_elements", {})
    missing = max(0, elements.get("total", 200) - elements.get("completed", 0))
    failures = (missing + metrics.get("uncompleted_upgrades", 1) +
                metrics.get("uncompleted_sigil_targets", 1) + metrics.get("unexplained_resources", 1) +
                int(metrics.get("prestige_proof") is not True) + int(report.get("verdict") != "pass"))
    elapsed = metrics.get("simulated_real_seconds", 0)
    if not number(elapsed):
        return (math.inf, math.inf, math.inf, math.inf)
    below_gate = int(elapsed <= 3600)
    distance = 0.0
    for name, band in targets.get("target", {}).items():
        key = "simulated_real_seconds" if name == "full_progression_seconds" else name
        value = metrics.get(key)
        if isinstance(band, dict):
            if not number(value):
                failures += 1
                continue
            lo, hi = band.get("min", 0), band.get("max", math.inf)
            distance += max(0, lo - value, value - hi) / max(1, lo if value < lo else hi)
        elif value != band:
            failures += 1
    change = 0.0
    for path, value in overrides.items():
        baseline = targets.get("parameters", {}).get(path, {}).get("baseline", value)
        change += abs(value - baseline) / max(1, abs(baseline))
    return (failures, below_gate, distance, change)


def next_candidate(profile, targets, parameter, iteration, increase=True):
    specs = targets.get("parameters", {})
    if parameter not in specs:
        raise ValueError("parameter is not allowlisted: " + parameter)
    spec = specs[parameter]
    if spec.get("direction") not in ("slower", "faster"):
        raise ValueError("invalid parameter direction")
    lo, hi, step = spec["min"], spec["max"], spec["step"]
    if not all(number(v) for v in (lo, hi, step)) or not lo < hi or step <= 0:
        raise ValueError("invalid parameter bounds")
    current = profile.get("overrides", {}).get(parameter, spec["baseline"])
    if not lo <= current <= hi:
        raise ValueError("current value outside parameter bounds")
    bound = hi if increase else lo
    value = current + (bound - current) / (2 ** iteration)
    value = min(hi, max(lo, lo + round((value - lo) / step) * step))
    value = round(value, 8)
    if value == current:
        return None
    candidate = copy.deepcopy(profile)
    candidate["name"] = "candidate-" + parameter.replace(".", "-") + "-" + str(iteration)
    candidate.setdefault("overrides", {})[parameter] = value
    return candidate


def same_trial_contract(before, after):
    return before.get("seed") == after.get("seed") and before.get("catalog_hash") == after.get("catalog_hash")


def direction_valid(before, after, direction, delta):
    if not same_trial_contract(before, after):
        return False
    old = before.get("metrics", {}).get("simulated_real_seconds")
    new = after.get("metrics", {}).get("simulated_real_seconds")
    if not number(old) or not number(new):
        return False
    sign = 1 if direction == "slower" else -1
    return (new - old) * delta * sign >= -1e-6


def fingerprint(report):
    stable = {key: report.get(key) for key in ("schema", "seed", "catalog_hash", "profile", "time", "metrics", "verdict")}
    stable["phase_verdicts"] = {key: {k: value.get(k) for k in ("state", "reason", "completed", "total")}
                                for key, value in report.get("phases", {}).items()}
    ledger = report.get("ledger", {})
    stable["ledger"] = {key: ledger.get(key) for key in ("operation_count", "counters", "resources", "events")}
    return hashlib.sha256(json.dumps(stable, sort_keys=True, allow_nan=False).encode()).hexdigest()


def write_new(path, value):
    with Path(path).open("x", encoding="utf-8") as file:
        json.dump(value, file, ensure_ascii=False, indent=2, allow_nan=False)


def validate_config(baseline, targets):
    if not isinstance(baseline, dict) or baseline.get("schema") != 1 or baseline.get("base") != "baseline" or not isinstance(baseline.get("overrides"), dict) or not isinstance(baseline.get("name"), str) or not baseline["name"].strip():
        raise ValueError("invalid baseline profile")
    if not isinstance(targets, dict) or not isinstance(targets.get("target"), dict) or not isinstance(targets.get("parameters"), dict):
        raise ValueError("invalid calibration configuration")
    for band in targets["target"].values():
        if isinstance(band, dict):
            if not band or set(band) - {"min", "max"} or not all(number(v) for v in band.values()) or band.get("min", 0) > band.get("max", math.inf):
                raise ValueError("invalid target band")
        elif type(band) is not bool and not number(band):
            raise ValueError("invalid target value")
    for value in baseline["overrides"].values():
        if not number(value):
            raise ValueError("invalid baseline override")
    for path, spec in targets["parameters"].items():
        if path not in ("ether.base_regen", "events.bench_interval", "retort.base_hours"):
            raise ValueError("parameter is not calibration-safe: " + path)
        if not isinstance(spec, dict) or not all(number(spec.get(k)) for k in ("min", "max", "step", "baseline")):
            raise ValueError("invalid parameter specification")
        if not spec["min"] < spec["max"] or spec["step"] <= 0 or spec.get("direction") not in ("faster", "slower"):
            raise ValueError("invalid parameter bounds/direction")
        current = baseline["overrides"].get(path, spec["baseline"])
        if not number(current) or not spec["min"] <= current <= spec["max"]:
            raise ValueError("baseline outside bounds")


def profile_matches(report, document, seed):
    profile = report.get("profile", {})
    return (report.get("seed") == seed and profile.get("name") == document.get("name")
            and profile.get("base") == document.get("base") and profile.get("schema") == document.get("schema")
            and profile.get("resolved_overrides") == document.get("overrides"))


def select_bottleneck(report, targets):
    metrics = report["metrics"]
    mapping = {"full_progression_seconds": ["retort.base_hours", "events.bench_interval", "ether.base_regen"],
               "active_player_seconds": ["events.bench_interval", "ether.base_regen"],
               "first_workshop_seconds": ["ether.base_regen", "events.bench_interval"],
               "first_retort_seconds": ["retort.base_hours"]}
    for target, band in targets["target"].items():
        if target not in mapping or not isinstance(band, dict):
            continue
        key = "simulated_real_seconds" if target == "full_progression_seconds" else target
        value = metrics.get(key)
        if not number(value):
            continue
        if value < band.get("min", 0):
            return mapping[target], True
        if value > band.get("max", math.inf):
            return mapping[target], False
    return [], False


def calibrate(baseline, targets, output, seed, max_trials, run):
    validate_config(baseline, targets)
    if max_trials < 1:
        raise ValueError("max_trials must be positive")
    output = Path(output)
    output.mkdir(parents=True, exist_ok=False)
    current = copy.deepcopy(baseline)
    trials = []
    best = None
    original = None
    previous = None
    changed_path = None
    brackets = {path: [spec["min"], spec["max"]] for path, spec in targets["parameters"].items()}
    visited = set()
    stop = "trial_limit"
    for index in range(1, max_trials + 1):
        directory = output / ("trial-%03d" % index)
        directory.mkdir()
        profile_path = directory / "profile.json"
        write_new(profile_path, current)
        report_path = directory / "report.json"
        exit_code = run(profile_path, seed, report_path)
        try:
            report = json.loads(report_path.read_text(encoding="utf-8"))
            errors = validate_report(report)
        except (OSError, ValueError) as error:
            report, errors = {}, [str(error)]
        if exit_code or errors:
            stop = "runner_failed" if exit_code else "invalid_report"
            write_new(directory / "verdict.json", {"accepted": False, "exit_code": exit_code, "errors": errors, "reason": stop})
            trials.append({"trial": index, "accepted": False, "reason": stop})
            break
        if original is None:
            original = report
        if not same_trial_contract(original, report) or not profile_matches(report, current, seed):
            stop = "calibration_invalid_contract"
        elif previous is not None and changed_path:
            spec = targets["parameters"][changed_path]
            delta = current["overrides"][changed_path] - previous["profile_value"]
            if report["profile"]["hash"] == previous["report"]["profile"]["hash"] and delta != 0:
                stop = "calibration_invalid_profile_hash"
            elif not direction_valid(previous["report"], report, spec["direction"], delta):
                stop = "calibration_invalid_direction"
            invariant_keys = ("discoveries", "sigils_crafted", "prestige_count")
            old_counts = previous["report"]["ledger"]["counters"]
            if any(report["ledger"]["counters"].get(k) != old_counts.get(k) for k in invariant_keys):
                stop = "calibration_invalid_counters"
        repeat = directory / "repeat"
        repeat.mkdir()
        repeat_exit = run(profile_path, seed, repeat / "report.json")
        try:
            repeated = json.loads((repeat / "report.json").read_text(encoding="utf-8"))
            if repeat_exit or validate_report(repeated) or fingerprint(report) != fingerprint(repeated):
                stop = "calibration_invalid_nondeterministic"
        except (OSError, ValueError):
            stop = "calibration_invalid_nondeterministic"
        objective = score(report, targets, current.get("overrides", {}))
        accepted = not stop.startswith("calibration_invalid") and objective[0] == 0 and objective[1] == 0
        entry = {"trial": index, "accepted": accepted, "objective": objective,
                 "profile_hash": report.get("profile", {}).get("hash"), "reason": stop}
        write_new(directory / "verdict.json", entry)
        trials.append(entry)
        if not accepted:
            stop = stop if stop.startswith("calibration_invalid") else "hard_gate_failed"
            break
        if best is None or tuple(objective) < tuple(best["objective"]):
            best = {**entry, "profile": copy.deepcopy(current)}
        if objective[2] == 0:
            stop = "target_reached"
            break
        if index == max_trials:
            break
        paths, need_slower = select_bottleneck(report, targets)
        candidate = None
        visited.add(json.dumps(current.get("overrides", {}), sort_keys=True))
        for path in paths:
            if path not in targets["parameters"]:
                continue
            spec = targets["parameters"][path]
            increase = need_slower == (spec["direction"] == "slower")
            value = current.get("overrides", {}).get(path, spec["baseline"])
            if increase:
                brackets[path][0] = max(brackets[path][0], value)
            else:
                brackets[path][1] = min(brackets[path][1], value)
            narrowed = copy.deepcopy(targets)
            narrowed["parameters"][path]["min"], narrowed["parameters"][path]["max"] = brackets[path]
            if brackets[path][0] >= brackets[path][1]:
                continue
            candidate = next_candidate(current, narrowed, path, 1, increase)
            if candidate is not None and json.dumps(candidate["overrides"], sort_keys=True) not in visited:
                changed_path = path
                previous = {"report": report, "profile_value": value}
                break
            candidate = None
        if candidate is None:
            stop = "parameter_bounds"
            break
        current = candidate
    summary = {"baseline_profile_hash": original.get("profile", {}).get("hash") if original else None,
               "best_profile_hash": best.get("profile_hash") if best else None,
               "trials": trials, "accepted_trials": sum(t["accepted"] for t in trials),
               "rejected_trials": sum(not t["accepted"] for t in trials),
               "objective_before": trials[0].get("objective") if trials else None,
               "objective_after": best.get("objective") if best else None,
               "changed_parameters": best["profile"].get("overrides", {}) if best else {},
               "stop_reason": stop}
    write_new(output / "summary.json", summary)
    if best and stop in ("target_reached", "trial_limit", "parameter_bounds"):
        write_new(output / "candidate.json", best["profile"])
    return summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, default=ROOT / "tools/balance_profiles/baseline.json")
    parser.add_argument("--targets", type=Path, default=ROOT / "tools/calibration_targets.json")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--max-trials", type=int, default=8)
    parser.add_argument("--godot")
    parser.add_argument("--timeout", type=float, default=600)
    args = parser.parse_args()
    try:
        baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
        targets = json.loads(args.targets.read_text(encoding="utf-8"))
        result = calibrate(baseline, targets, args.out, args.seed, args.max_trials,
                           lambda profile, seed, report: run_profile(profile, seed, report, args.godot, args.timeout))
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result["best_profile_hash"] and result["stop_reason"] in ("target_reached", "trial_limit", "parameter_bounds") else 2
    except (OSError, ValueError, KeyError) as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
