import argparse
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
PHASES = ("bootstrap/catalog", "discovery", "idle", "retort", "sigil", "prestige", "post_prestige_discovery", "proof")


def number(value):
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def validate_report(report):
    errors = []
    if not isinstance(report, dict):
        return ["report must be an object"]
    for key, kind in {"schema": int, "seed": int, "runner_commit": str, "catalog_hash": str,
                      "profile": dict, "time": dict, "ledger": dict, "phases": dict,
                      "metrics": dict, "verdict": str}.items():
        if type(report.get(key)) is not kind:
            errors.append("missing or invalid " + key)
    if errors:
        return errors
    if report["schema"] != 1 or report["verdict"] not in ("pass", "fail", "incomplete", "invalid_profile"):
        errors.append("unsupported schema or verdict")
    profile = report["profile"]
    if not re.fullmatch(r"[a-f0-9]{64}", str(report["catalog_hash"])):
        errors.append("invalid catalog hash")
    if not re.fullmatch(r"[a-f0-9]{64}", str(profile.get("hash", ""))):
        errors.append("invalid profile hash")
    for key, kind in {"schema": int, "name": str, "base": str, "resolved_overrides": dict}.items():
        if type(profile.get(key)) is not kind:
            errors.append("invalid profile." + key)
    for key in ("active_seconds", "offline_seconds"):
        if not number(report["time"].get(key)):
            errors.append("invalid time." + key)
    for key, kind in {"operation_count": int, "counters": dict, "resources": dict}.items():
        if type(report["ledger"].get(key)) is not kind:
            errors.append("invalid ledger." + key)
    metrics = report["metrics"]
    numeric = ("uncompleted_upgrades", "uncompleted_sigil_targets", "unexplained_resources",
               "simulated_real_seconds", "active_player_seconds")
    for key in numeric:
        if not number(metrics.get(key)):
            errors.append("invalid metrics." + key)
    elements = metrics.get("local_elements", {})
    if not isinstance(elements, dict) or any(type(elements.get(k)) is not int for k in ("completed", "total")):
        errors.append("invalid local element counts")
    elif not 0 <= elements["completed"] <= elements["total"] or elements["total"] != 200:
        errors.append("local catalog must contain exactly 200 targets")
    deficit = metrics.get("ether_deficit_at_completion")
    if "ether_deficit_at_completion" not in metrics or not (
            number(deficit) or deficit is None and report["verdict"] != "pass"):
        errors.append("invalid metrics.ether_deficit_at_completion")
    for proof in ("prestige_proof", "reload_proof", "replay_proof", "retort_queue_proof"):
        if type(metrics.get(proof)) is not bool:
            errors.append("invalid " + proof)
    recipes = metrics.get("recipes", {})
    if not isinstance(recipes, dict) or any(type(recipes.get(k)) is not int for k in ("completed", "total")):
        errors.append("invalid recipe counts")
    elif recipes["total"] != 196 or not 0 <= recipes["completed"] <= recipes["total"]:
        errors.append("invalid local recipe targets")
    for name in PHASES:
        phase = report["phases"].get(name)
        if not isinstance(phase, dict) or phase.get("state") not in ("pass", "fail", "incomplete", "blocked"):
            errors.append("missing or invalid phase " + name)
    if profile.get("schema") != 1 or profile.get("base") != "baseline":
        errors.append("unsupported profile schema/base")
    if errors:
        return errors
    if not report["runner_commit"].strip() or report["ledger"]["operation_count"] < 0:
        errors.append("invalid runner revision or operation count")
    if errors:
        return errors
    elapsed = report["time"]["active_seconds"] + report["time"]["offline_seconds"]
    if not math.isclose(metrics["simulated_real_seconds"], elapsed, rel_tol=1e-9, abs_tol=1e-5):
        errors.append("simulated time differs from active + offline timeline")
    if report["verdict"] == "pass":
        for key in ("discoveries", "sigils_crafted", "prestige_count"):
            value = report["ledger"]["counters"].get(key)
            if type(value) is not int or value < 0:
                errors.append("missing or invalid invariant counter " + key)
        if elements.get("completed") != 200:
            errors.append("false pass: incomplete catalog")
        for key in ("uncompleted_upgrades", "uncompleted_sigil_targets", "unexplained_resources", "ether_deficit_at_completion"):
            if metrics.get(key) != 0:
                errors.append("false pass: " + key)
        for proof in ("prestige_proof", "reload_proof", "replay_proof", "retort_queue_proof"):
            if metrics.get(proof) is not True:
                errors.append("false pass: " + proof)
        if recipes.get("completed") != recipes.get("total"):
            errors.append("false pass: incomplete recipes")
        if number(metrics.get("simulated_real_seconds")) and metrics["simulated_real_seconds"] <= 3600:
            errors.append("false pass: progression must exceed 60 minutes")
        if any(report["phases"].get(k, {}).get("state") != "pass" for k in PHASES):
            errors.append("false pass: incomplete phases")
    return errors


def format_output_line(line):
    if not line.startswith("[PROGRESS] "):
        return line
    try:
        status = json.loads(line[len("[PROGRESS] "):])
        percent = status["phase_percent"]
        if not number(percent):
            return line
        return (f"{status['phase']} | {percent:g}% | {status['completed']}/{status['total']} | "
                f"{status.get('last_event', '')}\n")
    except (ValueError, KeyError, TypeError):
        return line


def finalize_timeout_report(report_path):
    report_path = Path(report_path)
    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        report = {}
    if not isinstance(report, dict):
        report = {}
    report["verdict"] = "fail"
    report["state"] = "fail"
    report["reason"] = "launcher_timeout"
    temp = report_path.with_name(report_path.name + ".tmp")
    temp.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(temp, report_path)


def execute_runner(command, report_path, run_dir, timeout=600, expected_seed=None, expected_profile=None,
                   report_validator=validate_report):
    report_path, run_dir = Path(report_path), Path(run_dir)
    if report_path.exists():
        raise FileExistsError("report already exists: " + str(report_path))
    if not number(timeout) or timeout <= 0:
        raise ValueError("timeout must be positive and finite")
    run_dir.mkdir(parents=True, exist_ok=False)
    env = os.environ.copy()
    for key, name in (("APPDATA", "appdata"), ("LOCALAPPDATA", "localappdata"),
                      ("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                      ("XDG_CACHE_HOME", "cache"), ("HOME", "home"), ("USERPROFILE", "home")):
        target = run_dir / name
        target.mkdir(exist_ok=True)
        env[key] = str(target.resolve())
    env["ALCHEMY_SERVER"] = ""
    started = time.monotonic()
    with (run_dir / "godot.log").open("w", encoding="utf-8") as log:
        proc = subprocess.Popen(command, cwd=ROOT, env=env, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, encoding="utf-8", errors="replace", bufsize=1,
                                start_new_session=os.name != "nt")
        timed_out = threading.Event()
        script_error = False

        def terminate_owned_child():
            timed_out.set()
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            else:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

        timer = threading.Timer(timeout, terminate_owned_child)
        timer.start()
        try:
            for line in proc.stdout:
                script_error = script_error or "SCRIPT ERROR:" in line
                log.write(line)
                log.flush()
                print(format_output_line(line), end="", flush=True)
            exit_code = proc.wait()
        finally:
            timer.cancel()
            proc.stdout.close()
        if timed_out.is_set():
            exit_code = 124
            finalize_timeout_report(report_path)
    errors = []
    report = None
    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
        errors = report_validator(report)
        if isinstance(report, dict):
            if expected_seed is not None and report.get("seed") != expected_seed:
                errors.append("report seed differs from invocation")
            if expected_profile is not None:
                actual = report.get("profile", {})
                if not isinstance(actual, dict) or any(actual.get(key) != expected_profile.get(source) for key, source in
                        (("schema", "schema"), ("base", "base"), ("name", "name"), ("resolved_overrides", "overrides"))):
                    errors.append("report profile differs from invocation")
    except (OSError, ValueError) as error:
        errors.append(str(error))
    if script_error:
        errors.append("Godot reported a script error")
    summary = {"exit_code": exit_code, "report": str(report_path.resolve()),
               "wall_clock_seconds": time.monotonic() - started,
               "verdict": report.get("verdict") if isinstance(report, dict) else "missing_report",
               "validation_errors": errors}
    (run_dir / "launcher.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False), flush=True)
    if exit_code != 0:
        return exit_code
    return 2 if errors or report.get("verdict") != "pass" else 0


def find_godot(explicit=None):
    found = explicit or os.environ.get("GODOT_BIN") or shutil.which("godot")
    if found:
        return str(Path(found).resolve())
    tools = ROOT.parents[2] / "godot-tools"
    candidates = sorted(tools.glob("Godot*_console.exe"))
    if not candidates:
        raise FileNotFoundError("Godot not found; pass --godot or set GODOT_BIN")
    return str(candidates[-1])


def progress_path_for(report):
    report = Path(report)
    return report.parent / (report.stem + "-run") / "progress.json"


def run_profile(profile, seed, report, godot=None, timeout=600, mutation=None):
    report = Path(report).resolve()
    report.parent.mkdir(parents=True, exist_ok=True)
    progress = progress_path_for(report)
    command = [find_godot(godot), "--headless", "--path", str(ROOT),
               "res://tests/progression_runner.tscn", "--", "--selftest",
               "--profile=" + str(Path(profile).resolve()), "--seed=" + str(seed),
               "--report=" + str(report), "--progress=" + str(progress)]
    if mutation:
        command.append("--mutation=" + mutation)
    run_dir = progress.parent
    print("Progress: " + str(progress), flush=True)
    document = json.loads(Path(profile).read_text(encoding="utf-8"))
    return execute_runner(command, report, run_dir, timeout, seed, document)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", type=Path, default=ROOT / "tools/balance_profiles/baseline.json")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--godot")
    parser.add_argument("--timeout", type=float, default=600)
    parser.add_argument("--mutation")
    parser.add_argument("--validate", type=Path)
    args = parser.parse_args()
    if args.validate:
        errors = validate_report(json.loads(args.validate.read_text(encoding="utf-8")))
        print(json.dumps(errors, ensure_ascii=False))
        return 2 if errors else 0
    report = args.report or ROOT / "previews/progression" / (str(time.time_ns()) + "-" + str(os.getpid())) / "report.json"
    try:
        return run_profile(args.profile, args.seed, report, args.godot, args.timeout, args.mutation)
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
