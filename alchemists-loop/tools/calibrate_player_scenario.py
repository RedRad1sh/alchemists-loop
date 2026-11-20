import argparse
import copy
import hashlib
import json
import math
import re
import sys
from pathlib import Path

from run_player_scenario import DEFAULT_SCENARIO, ROOT, run_profile


HASH_RE = re.compile(r"^[a-f0-9]{64}$")

CALIBRATION_SAFE_PARAMETERS = {
    "ether.base_regen",
    "events.bench_interval",
    "retort.base_hours",
    "player.action_seconds",
    "discovery.cost",
    "ether.regen_per_upgrade",
    "milestones.regen20",
    "milestones.regen57",
    "ether.max_ether",
    "spring.offline_window_sec.0",
    "spring.volume_cap.0",
    "spring.volume_cap.1",
    "spring.volume_cap.2",
    "upgrades.items.0.base",
}


def numeric(value):
    return type(value) in (int, float) and math.isfinite(value)


def metric_value(report, name):
    if name == "first_upgrade_seconds":
        origin = report.get("before", {}).get("clock", {}).get("now", 0.0)
        if not numeric(origin):
            return None
        values = []
        for segment in report.get("segments", []):
            for event in segment.get("events", []):
                if isinstance(event, dict) and event.get("kind") == "upgrade":
                    at = event.get("at")
                    if numeric(at):
                        values.append(float(at) - float(origin))
        if isinstance(report.get("events"), list):
            for event in report["events"]:
                if isinstance(event, dict) and event.get("kind") == "upgrade":
                    at = event.get("at")
                    if numeric(at):
                        values.append(float(at) - float(origin))
        return min(values) if values else None

    if name.startswith("first_upgrade_seconds."):
        upgrade_id = name.split(".", 2)[2]
        origin = report.get("before", {}).get("clock", {}).get("now", 0.0)
        values = []
        for segment in report.get("segments", []):
            for event in segment.get("events", []):
                if (isinstance(event, dict) and event.get("kind") == "upgrade"
                        and str(event.get("upgrade", "")) == upgrade_id
                        and numeric(event.get("at")) and numeric(origin)):
                    values.append(float(event["at"]) - float(origin))
        return min(values) if values else None

    counters = report.get("session", {}).get("counters", {})
    if name in counters:
        return counters[name]
    time_data = report.get("time", {})
    if name in time_data:
        return time_data[name]
    metrics = report.get("metrics", {})
    if name in metrics:
        return metrics[name]
    if name in report:
        return report[name]
    if name == "offline_ether_earned":
        return sum(segment.get("offline_granted", {}).get("ether", 0)
                   for segment in report.get("segments", []))
    if name == "offline_ether_spent":
        return sum(segment.get("offline_spent", {}).get("ether", 0)
                   for segment in report.get("segments", []))
    return None


def next_candidate(profile, targets, parameter, iteration, increase=True):
    specs = targets.get("parameters", {})
    if parameter not in specs:
        raise ValueError("parameter is not allowlisted: " + parameter)
    spec = specs[parameter]
    if spec.get("direction") not in ("slower", "faster"):
        raise ValueError("invalid parameter direction")
    lo, hi, step = (spec.get("min"), spec.get("max"), spec.get("step"))
    if not all(numeric(value) for value in (lo, hi, step)) or not lo < hi or step <= 0:
        raise ValueError("invalid parameter bounds")
    current = profile.get("overrides", {}).get(parameter, spec.get("baseline"))
    if not numeric(current) or not lo <= current <= hi:
        raise ValueError("current value outside parameter bounds")
    bound = hi if increase else lo
    value = current + (bound - current) / (2 ** max(1, int(iteration)))
    value = min(hi, max(lo, lo + round((value - lo) / step) * step))
    value = round(value, 8)
    if value == current:
        return None
    candidate = copy.deepcopy(profile)
    candidate["name"] = "candidate-" + parameter.replace(".", "-") + "-" + str(iteration)
    candidate.setdefault("overrides", {})[parameter] = value
    return candidate


def validate_config(baseline, targets):
    if (not isinstance(baseline, dict) or baseline.get("schema") != 1
            or baseline.get("base") != "baseline"
            or not isinstance(baseline.get("name"), str)
            or not baseline["name"].strip()
            or not isinstance(baseline.get("overrides"), dict)):
        raise ValueError("invalid baseline profile")
    if (not isinstance(targets, dict) or not isinstance(targets.get("target"), dict)
            or not targets["target"] or not isinstance(targets.get("parameters"), dict)
            or not targets["parameters"]):
        raise ValueError("invalid calibration configuration")

    for path, value in baseline["overrides"].items():
        if path not in CALIBRATION_SAFE_PARAMETERS:
            raise ValueError("parameter is not calibration-safe: " + str(path))
        if not numeric(value):
            raise ValueError("invalid baseline override: " + str(path))

    for band in targets["target"].values():
        if isinstance(band, dict):
            if (not band or set(band) - {"min", "max"}
                    or not all(numeric(value) for value in band.values())
                    or band.get("min", 0) > band.get("max", math.inf)):
                raise ValueError("invalid target band")
        elif type(band) is not bool and not numeric(band):
            raise ValueError("invalid target value")

    for path, spec in targets["parameters"].items():
        if path not in CALIBRATION_SAFE_PARAMETERS:
            raise ValueError("parameter is not calibration-safe: " + path)
        if not isinstance(spec, dict):
            raise ValueError("invalid parameter specification")
        required = ("min", "max", "step", "baseline")
        if not all(numeric(spec.get(key)) for key in required):
            raise ValueError("invalid parameter specification")
        if (not spec["min"] < spec["max"] or spec["step"] <= 0
                or spec.get("direction") not in ("faster", "slower")):
            raise ValueError("invalid parameter bounds/direction")
        if not spec["min"] <= spec["baseline"] <= spec["max"]:
            raise ValueError("parameter baseline outside bounds")
        current = baseline["overrides"].get(path, spec["baseline"])
        if not numeric(current) or not spec["min"] <= current <= spec["max"]:
            raise ValueError("baseline outside bounds: " + path)


def fingerprint(report):
    stable = {
        key: report.get(key)
        for key in ("schema", "scenario", "seed", "catalog_hash", "profile",
                    "definition", "before", "after", "delta", "time",
                    "segments", "available_goals", "blocked_goals", "session",
                    "errors", "verdict")
    }
    return hashlib.sha256(json.dumps(
        stable, ensure_ascii=False, sort_keys=True, separators=(",", ":"),
        allow_nan=False).encode("utf-8")).hexdigest()


def validate_report_contract(report, seed, profile):
    errors = []
    if not isinstance(report, dict):
        return ["report must be an object"]
    for key, kind in (("seed", int), ("catalog_hash", str), ("profile", dict),
                      ("verdict", str)):
        if type(report.get(key)) is not kind:
            errors.append("missing or invalid " + key)
    if errors:
        return errors
    if report["seed"] != seed:
        errors.append("report seed differs from invocation")
    if not HASH_RE.fullmatch(report["catalog_hash"]):
        errors.append("invalid catalog hash")
    if report["verdict"] != "pass":
        errors.append("runner verdict is not pass")
    actual = report["profile"]
    for key, expected in (("schema", profile.get("schema")), ("base", profile.get("base")),
                          ("name", profile.get("name")), ("resolved_overrides", profile.get("overrides"))):
        if actual.get(key) != expected:
            errors.append("report profile differs from invocation: " + key)
    if not HASH_RE.fullmatch(str(actual.get("hash", ""))):
        errors.append("invalid profile hash")
    return errors


def objective(report, targets, profile):
    failures = 0
    distance = 0.0
    for name, band in targets.get("target", {}).items():
        value = metric_value(report, name)
        if isinstance(band, dict):
            if not numeric(value):
                failures += 1
                continue
            low, high = band.get("min", 0), band.get("max", math.inf)
            if value < low:
                distance += (low - value) / max(1.0, abs(low))
            elif value > high:
                distance += (value - high) / max(1.0, abs(high))
        elif value != band:
            failures += 1
    change = 0.0
    for path, value in profile.get("overrides", {}).items():
        baseline = targets.get("parameters", {}).get(path, {}).get("baseline", value)
        change += abs(float(value) - float(baseline)) / max(1.0, abs(float(baseline)))
    return failures, distance, change


def in_target(report, targets):
    return objective(report, targets, {})[0] == 0 and objective(report, targets, {})[1] == 0


def direction_valid(before, after, target_name, direction, delta):
    old = metric_value(before, target_name)
    new = metric_value(after, target_name)
    if not numeric(old) or not numeric(new) or delta == 0:
        return False
    sign = 1 if direction == "slower" else -1
    return (float(new) - float(old)) * delta * sign >= -1e-6


def write_new(path, value):
    with Path(path).open("x", encoding="utf-8") as file:
        json.dump(value, file, ensure_ascii=False, indent=2, allow_nan=False)


def load_report(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _read_trial(report_path, exit_code, seed, profile):
    try:
        report = load_report(report_path)
    except (OSError, ValueError) as error:
        return {}, [str(error)]
    errors = validate_report_contract(report, seed, profile)
    if exit_code:
        errors.append("runner exit code: " + str(exit_code))
    return report, errors


def calibrate(baseline, targets, output, seed, max_trials, run):
    validate_config(baseline, targets)
    if type(seed) is not int:
        raise ValueError("seed must be an integer")
    if type(max_trials) is not int or max_trials < 1:
        raise ValueError("max_trials must be positive")
    output = Path(output)
    output.mkdir(parents=True, exist_ok=False)

    current = copy.deepcopy(baseline)
    trials = []
    best = None
    first_report = None
    previous_by_parameter = {}
    brackets = {
        path: [spec["min"], spec["max"]]
        for path, spec in targets["parameters"].items()
    }
    visited = set()
    stop = "trial_limit"
    parameter_order = list(targets["parameters"])

    for index in range(1, max_trials + 1):
        directory = output / ("trial-%03d" % index)
        directory.mkdir()
        profile_path = directory / "profile.json"
        write_new(profile_path, current)
        report_path = directory / "report.json"
        try:
            exit_code = run(profile_path, seed, report_path)
        except Exception as error:
            exit_code = 2
            report_path.write_text(json.dumps({"verdict": "fail", "reason": str(error)}), encoding="utf-8")
        report, errors = _read_trial(report_path, exit_code, seed, current)
        if not errors and first_report is None:
            first_report = report
        changed_path = None
        for path in targets["parameters"]:
            before_value = baseline["overrides"].get(path, targets["parameters"][path]["baseline"])
            current_value = current["overrides"].get(path, targets["parameters"][path]["baseline"])
            if current_value != before_value:
                changed_path = path
                break
        if not errors and changed_path is not None:
            previous = previous_by_parameter.get(changed_path)
            if previous is not None:
                spec = targets["parameters"][changed_path]
                delta = current["overrides"].get(changed_path, spec["baseline"]) - previous["value"]
                if report["profile"].get("hash") == previous["report"]["profile"].get("hash") and delta != 0:
                    errors.append("calibration_invalid_profile_hash")
                elif not direction_valid(previous["report"], report, next(iter(targets["target"])), spec["direction"], delta):
                    errors.append("calibration_invalid_direction")
        if not errors:
            repeat = directory / "repeat"
            repeat.mkdir()
            repeat_report_path = repeat / "report.json"
            try:
                repeat_exit = run(profile_path, seed, repeat_report_path)
            except Exception:
                repeat_exit = 2
            repeated, repeat_errors = _read_trial(repeat_report_path, repeat_exit, seed, current)
            if repeat_errors or fingerprint(report) != fingerprint(repeated):
                errors.append("calibration_invalid_nondeterministic")

        if errors:
            stop = errors[0] if errors[0].startswith("calibration_invalid") else "calibration_invalid_contract"
            entry = {"trial": index, "accepted": False, "reason": stop, "errors": errors}
            write_new(directory / "verdict.json", entry)
            trials.append(entry)
            break

        trial_objective = objective(report, targets, current)
        entry = {"trial": index, "accepted": True, "objective": trial_objective,
                 "metric_values": {name: metric_value(report, name) for name in targets["target"]},
                 "profile_hash": report["profile"].get("hash"), "reason": ""}
        write_new(directory / "verdict.json", entry)
        trials.append(entry)
        for path in targets["parameters"]:
            value = current["overrides"].get(path, targets["parameters"][path]["baseline"])
            previous_by_parameter[path] = {"value": value, "report": report}
        if best is None or tuple(trial_objective) < tuple(best["objective"]):
            best = {**entry, "profile": copy.deepcopy(current)}
        if in_target(report, targets):
            stop = "target_reached"
            break
        if index == max_trials:
            break

        target_name, target_band = next(iter(targets["target"].items()))
        value = metric_value(report, target_name)
        if not numeric(value):
            stop = "calibration_invalid_metric"
            break
        if isinstance(target_band, dict):
            need_slower = value < target_band.get("min", 0)
            need_faster = value > target_band.get("max", math.inf)
        else:
            need_slower = value < target_band
            need_faster = value > target_band
        candidate = None
        for path_index, path in enumerate(parameter_order):
            spec = targets["parameters"][path]
            current_value = current["overrides"].get(path, spec["baseline"])
            if need_slower:
                increase = spec["direction"] == "slower"
            elif need_faster:
                increase = spec["direction"] == "faster"
            else:
                break
            if increase:
                brackets[path][0] = max(brackets[path][0], current_value)
            else:
                brackets[path][1] = min(brackets[path][1], current_value)
            if brackets[path][0] >= brackets[path][1]:
                continue
            narrowed = copy.deepcopy(targets)
            narrowed["parameters"][path]["min"], narrowed["parameters"][path]["max"] = brackets[path]
            candidate = next_candidate(current, narrowed, path, 1, increase)
            if candidate is None:
                continue
            key = json.dumps(candidate.get("overrides", {}), sort_keys=True)
            if key in visited:
                candidate = None
                continue
            break
        if candidate is None:
            stop = "parameter_bounds"
            break
        visited.add(json.dumps(current.get("overrides", {}), sort_keys=True))
        candidate["name"] = "trial-%03d" % (index + 1)
        current = candidate

    summary = {
        "baseline_profile_hash": first_report.get("profile", {}).get("hash") if first_report else None,
        "best_profile_hash": best.get("profile_hash") if best else None,
        "trials": trials,
        "accepted_trials": sum(item["accepted"] for item in trials),
        "rejected_trials": sum(not item["accepted"] for item in trials),
        "objective_before": trials[0].get("objective") if trials else None,
        "objective_after": best.get("objective") if best else None,
        "changed_parameters": best["profile"].get("overrides", {}) if best else {},
        "stop_reason": stop,
    }
    write_new(output / "summary.json", summary)
    if best and stop in ("target_reached", "trial_limit", "parameter_bounds"):
        write_new(output / "candidate.json", best["profile"])
    return summary


def main():
    parser = argparse.ArgumentParser(description="Calibrate player-facing active/offline balance scenarios")
    parser.add_argument("--baseline", type=Path, default=ROOT / "tools/balance_profiles/calibrated.json")
    parser.add_argument("--targets", type=Path, default=ROOT / "tools/player_scenario_calibration_targets.json")
    parser.add_argument("--scenario", type=Path, default=DEFAULT_SCENARIO)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=31)
    parser.add_argument("--max-trials", type=int, default=8)
    parser.add_argument("--godot")
    parser.add_argument("--timeout", type=float, default=120)
    args = parser.parse_args()
    try:
        baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
        targets = json.loads(args.targets.read_text(encoding="utf-8"))
        result = calibrate(
            baseline,
            targets,
            args.out,
            args.seed,
            args.max_trials,
            lambda profile, seed, report: run_profile(
                profile, seed, args.scenario, report, args.godot, args.timeout
            ),
        )
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result.get("best_profile_hash") and result["stop_reason"] in (
            "target_reached", "trial_limit", "parameter_bounds"
        ) else 2
    except (OSError, ValueError, KeyError) as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
