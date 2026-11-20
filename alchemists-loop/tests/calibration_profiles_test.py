import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))


def load_tool(name):
    path = ROOT / "tools" / (name + ".py")
    if not path.exists():
        return None
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def passing_report():
    return {
        "schema": 1, "seed": 1, "runner_commit": "test-revision",
        "catalog_hash": "a" * 64,
        "profile": {"name": "baseline", "schema": 1, "base": "baseline",
                    "hash": "b" * 64, "resolved_overrides": {}},
        "time": {"active_seconds": 2000, "offline_seconds": 28000},
        "ledger": {"operation_count": 2, "counters": {"brews": 2, "discoveries": 196, "sigils_crafted": 1, "prestige_count": 1},
                   "resources": {}, "events": []},
        "phases": {name: {"state": "pass"} for name in
                   ["bootstrap/catalog", "discovery", "idle", "retort", "sigil", "prestige", "post_prestige_discovery", "proof"]},
        "metrics": {"local_elements": {"completed": 200, "total": 200},
                    "uncompleted_upgrades": 0, "uncompleted_sigil_targets": 0,
                    "prestige_proof": True, "reload_proof": True, "replay_proof": True, "retort_queue_proof": True,
                    "recipes": {"completed": 196, "total": 196}, "unexplained_resources": 0,
                    "simulated_real_seconds": 30000, "active_player_seconds": 2000,
                    "first_workshop_seconds": 500, "first_retort_seconds": 28800,
                    "ether_deficit_at_completion": 0},
        "verdict": "pass",
    }


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.tool = load_tool("run_progression_runner")
        self.assertIsNotNone(self.tool, "launcher implementation is missing")

    def test_live_progress_has_readable_phase_percentage(self):
        line = '[PROGRESS] {"phase":"discovery","percent":12.5,"phase_percent":37.5,"completed":75,"total":200,"last_event":"steam"}'
        text = self.tool.format_output_line(line)
        self.assertIn("discovery", text)
        self.assertIn("37.5%", text)
        self.assertIn("75/200", text)
        self.assertIn("steam", text)
        self.assertEqual(self.tool.format_output_line("Godot diagnostic"), "Godot diagnostic")
        self.assertEqual(self.tool.format_output_line("[PROGRESS] not-json"), "[PROGRESS] not-json")

    def test_report_validation_rejects_missing_and_nonfinite_fields(self):
        self.assertEqual(self.tool.validate_report(passing_report()), [])
        for key in ["profile", "catalog_hash", "seed", "time", "ledger", "phases", "verdict"]:
            report = passing_report()
            del report[key]
            self.assertTrue(self.tool.validate_report(report), key)
        for value in [float("nan"), float("inf"), -1, True, "30000"]:
            report = passing_report()
            report["metrics"]["simulated_real_seconds"] = value
            self.assertTrue(self.tool.validate_report(report), repr(value))

    def test_incomplete_report_allows_only_unknown_ether_deficit(self):
        report = passing_report()
        report["verdict"] = "incomplete"
        report["metrics"]["ether_deficit_at_completion"] = None
        self.assertEqual(self.tool.validate_report(report), [])
        report["verdict"] = "pass"
        self.assertTrue(self.tool.validate_report(report))

    def test_false_pass_is_rejected(self):
        for field, value in [("uncompleted_upgrades", 1), ("uncompleted_sigil_targets", 1),
                             ("unexplained_resources", 1), ("prestige_proof", False),
                             ("simulated_real_seconds", 3600)]:
            report = passing_report()
            report["metrics"][field] = value
            self.assertTrue(self.tool.validate_report(report), field)
        report = passing_report()
        report["phases"]["retort"]["state"] = "incomplete"
        self.assertTrue(self.tool.validate_report(report))
        report = passing_report()
        report["metrics"]["local_elements"]["completed"] = 199
        self.assertTrue(self.tool.validate_report(report))

    def test_pass_requires_reload_replay_recipes_and_second_world(self):
        for field in ("reload_proof", "replay_proof", "retort_queue_proof"):
            report = passing_report()
            report["metrics"][field] = False
            self.assertTrue(self.tool.validate_report(report), field)
        report = passing_report()
        report["metrics"]["recipes"]["completed"] = 195
        self.assertTrue(self.tool.validate_report(report))
        report = passing_report()
        del report["phases"]["post_prestige_discovery"]
        self.assertTrue(self.tool.validate_report(report))

    def test_exit_zero_does_not_hide_missing_report_and_nonzero_is_preserved(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp)
            result = self.tool.execute_runner(
                [sys.executable, "-c", "print('no report')"], out / "missing.json", out / "a", 5)
            self.assertNotEqual(result, 0)
            result = self.tool.execute_runner(
                [sys.executable, "-c", "import sys;sys.exit(7)"], out / "missing2.json", out / "b", 5)
            self.assertEqual(result, 7)

    def test_script_error_cannot_hide_behind_pass_report(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp)
            report = out / "report.json"
            code = ("import pathlib; print('SCRIPT ERROR: injected failure'); "
                    f"pathlib.Path({str(report)!r}).write_text({json.dumps(passing_report())!r})")
            self.assertNotEqual(self.tool.execute_runner([sys.executable, "-c", code], report, out / "run", 5), 0)

    def test_production_counter_names_are_accepted(self):
        report = passing_report()
        self.assertEqual(report["ledger"]["counters"]["sigils_crafted"], 1)
        self.assertEqual(report["ledger"]["counters"]["prestige_count"], 1)
        self.assertEqual(self.tool.validate_report(report), [])

    def test_pass_report_requires_typed_invariant_counters(self):
        for value in [None, "1", -1, True]:
            report = passing_report()
            report["ledger"]["counters"]["sigils_crafted"] = value
            self.assertTrue(self.tool.validate_report(report))
        report = passing_report()
        del report["ledger"]["counters"]["prestige_count"]
        self.assertTrue(self.tool.validate_report(report))

    def test_report_cannot_inflate_simulated_time(self):
        report = passing_report()
        report["metrics"]["simulated_real_seconds"] = 999999
        self.assertTrue(self.tool.validate_report(report))

    def test_child_output_and_appdata_are_isolated(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp)
            report = out / "report.json"
            code = ("import os,json,pathlib; "
                    "print('STREAMED'); "
                    f"pathlib.Path({str(report)!r}).write_text({json.dumps(passing_report())!r}); "
                    "pathlib.Path(os.environ['APPDATA']).joinpath('child-marker').write_text('ok')")
            result = self.tool.execute_runner(
                [sys.executable, "-c", code], report, out / "isolated", 5)
            self.assertEqual(result, 0)
            self.assertTrue((out / "isolated" / "appdata" / "child-marker").exists())
            self.assertIn("STREAMED", (out / "isolated" / "godot.log").read_text())

    def test_launcher_rejects_report_from_wrong_invocation(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp)
            report = out / "report.json"
            code = f"import pathlib;pathlib.Path({str(report)!r}).write_text({json.dumps(passing_report())!r})"
            result = self.tool.execute_runner([sys.executable, "-c", code], report, out / "isolated", 5,
                                             expected_seed=99)
            self.assertNotEqual(result, 0)

    def test_malformed_nested_report_fails_closed(self):
        for section, key, value in [("metrics", "local_elements", []), ("phases", "proof", None),
                                    ("profile", "schema", 2), ("profile", "base", "other"),
                                    ("ledger", "operation_count", -1), ("ledger", "operation_count", "wrong")]:
            report = passing_report()
            report[section][key] = value
            self.assertTrue(self.tool.validate_report(report))

    def test_progress_paths_are_unique_and_do_not_alias_report(self):
        first = self.tool.progress_path_for(Path("/tmp/a.json"))
        second = self.tool.progress_path_for(Path("/tmp/b.json"))
        self.assertNotEqual(first, second)
        self.assertNotEqual(self.tool.progress_path_for(Path("/tmp/progress.json")), Path("/tmp/progress.json"))

    def test_timeout_cannot_leave_owned_descendant_holding_stdout(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp)
            code = "import subprocess,sys,threading;subprocess.Popen([sys.executable,'-c','import threading;threading.Event().wait(2)']);threading.Event().wait(60)"
            import time
            started = time.monotonic()
            result = self.tool.execute_runner([sys.executable, "-c", code], out / "report.json", out / "run", .5)
            self.assertEqual(result, 124)
            self.assertLess(time.monotonic() - started, 1.7)

    def test_timeout_terminates_only_owned_child(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp)
            code = "import threading; threading.Event().wait(60)"
            self.assertEqual(self.tool.execute_runner(
                [sys.executable, "-c", code], out / "report.json", out / "isolated", .2), 124)

    def test_timeout_finalizes_intermediate_report_as_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp)
            report = out / "report.json"
            code = ("import pathlib,threading; "
                    f"pathlib.Path({str(report)!r}).write_text({json.dumps(passing_report())!r}); "
                    "threading.Event().wait(60)")
            self.assertEqual(self.tool.execute_runner(
                [sys.executable, "-c", code], report, out / "isolated", .2), 124)
            finalized = json.loads(report.read_text())
            self.assertEqual(finalized["verdict"], "fail")
            self.assertEqual(finalized["state"], "fail")
            self.assertEqual(finalized["reason"], "launcher_timeout")


class PlayerScenarioCalibrationTests(unittest.TestCase):
    def setUp(self):
        self.tool = load_tool("calibrate_player_scenario")
        self.assertIsNotNone(self.tool, "player scenario calibration implementation is missing")

    def test_first_upgrade_metric_uses_earliest_upgrade_event(self):
        report = {"before": {"clock": {"now": 1000}},
                  "segments": [{"events": [{"kind": "upgrade", "at": 2200},
                                               {"kind": "upgrade", "at": 1500}]}]}
        self.assertEqual(self.tool.metric_value(report, "first_upgrade_seconds"), 500)

    def test_next_candidate_preserves_profile_and_stays_on_step(self):
        baseline = {"schema": 1, "name": "baseline", "base": "baseline", "overrides": {}}
        targets = {"parameters": {"player.action_seconds": {"min": 0.5, "max": 3.0,
                                                               "step": 0.5, "baseline": 1.0,
                                                               "direction": "slower"}}}
        candidate = self.tool.next_candidate(baseline, targets, "player.action_seconds", 1)
        self.assertEqual(candidate["overrides"], {"player.action_seconds": 2.0})
        self.assertEqual(baseline["overrides"], {})

    def test_validate_config_rejects_parameter_outside_profile_contract(self):
        baseline = {"schema": 1, "name": "baseline", "base": "baseline", "overrides": {}}
        targets = {"target": {"first_upgrade_seconds": {"min": 900, "max": 1500}},
                   "parameters": {"unknown.path": {"min": 0, "max": 1, "step": 1,
                                                     "baseline": 0, "direction": "slower"}}}
        with self.assertRaises(ValueError):
            self.tool.validate_config(baseline, targets)

    def test_calibration_keeps_trials_and_repeats_fingerprint(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp) / "trials"
            baseline = {"schema": 1, "name": "baseline", "base": "baseline", "overrides": {}}
            targets = {"target": {"first_upgrade_seconds": {"min": 900, "max": 1500}},
                       "parameters": {"player.action_seconds": {"min": 0.5, "max": 3.0,
                                                                      "step": 0.5, "baseline": 1.0,
                                                                      "direction": "slower"}}}
            calls = []

            def run(profile, seed, report):
                calls.append(Path(report))
                doc = json.loads(Path(profile).read_text(encoding="utf-8"))
                value = doc["overrides"].get("player.action_seconds", 1.0)
                data = {"schema": 1, "scenario": 1, "seed": seed, "catalog_hash": "a" * 64,
                        "profile": {"schema": 1, "name": doc["name"], "base": "baseline",
                                    "hash": "%064x" % int(value * 10),
                                    "resolved_overrides": doc["overrides"]},
                        "verdict": "pass", "time": {"active_seconds": 7200,
                        "offline_seconds": 18000, "simulated_real_seconds": 25200},
                        "segments": [{"events": [{"kind": "upgrade", "at": 1000 + value * 1000}]}]}
                Path(report).write_text(json.dumps(data), encoding="utf-8")
                return 0

            result = self.tool.calibrate(baseline, targets, out, 31, 2, run)
            self.assertTrue((out / "trial-001" / "repeat" / "report.json").exists())
            self.assertGreaterEqual(len(calls), 2)
            self.assertIn(result["stop_reason"], ["target_reached", "trial_limit", "parameter_bounds"])


class CalibrationTests(unittest.TestCase):
    def setUp(self):
        self.tool = load_tool("calibrate_progression")
        self.assertIsNotNone(self.tool, "calibration implementation is missing")
        self.targets = {
            "target": {"full_progression_seconds": {"min": 21600, "max": 259200}},
            "parameters": {"retort.base_hours": {"min": 8, "max": 24, "step": 1,
                                                    "baseline": 12, "direction": "slower"}},
        }

    def test_score_hard_gates_outrank_time(self):
        good = passing_report()
        broken = copy.deepcopy(good)
        broken["metrics"]["unexplained_resources"] = 1
        self.assertLess(self.tool.score(good, self.targets, {}),
                        self.tool.score(broken, self.targets, {}))
        too_fast = passing_report()
        too_fast["metrics"]["simulated_real_seconds"] = 1000
        self.assertLess(self.tool.score(good, self.targets, {}),
                        self.tool.score(too_fast, self.targets, {}))

    def test_one_coordinate_respects_bounds_and_preserves_baseline(self):
        baseline = {"schema": 1, "name": "baseline", "base": "baseline", "overrides": {}}
        untouched = copy.deepcopy(baseline)
        candidate = self.tool.next_candidate(baseline, self.targets, "retort.base_hours", 1)
        self.assertEqual(candidate["overrides"], {"retort.base_hours": 18})
        self.assertEqual(baseline, untouched)
        self.assertIsNone(self.tool.next_candidate(candidate, self.targets, "retort.base_hours", 20))
        with self.assertRaises(ValueError):
            self.tool.next_candidate(baseline, self.targets, "discovery.daily_limit", 1)

    def test_direction_and_seed_catalog_checks(self):
        before = passing_report()
        after = passing_report()
        after["metrics"]["simulated_real_seconds"] = 20000
        self.assertFalse(self.tool.direction_valid(before, after, "slower", 1))
        self.assertTrue(self.tool.direction_valid(before, after, "slower", -1))
        after["catalog_hash"] = "c" * 64
        self.assertFalse(self.tool.same_trial_contract(before, after))
        after = passing_report()
        after["seed"] = 2
        self.assertFalse(self.tool.same_trial_contract(before, after))

    def test_fingerprint_ignores_wall_clock_not_gameplay(self):
        before = passing_report()
        after = passing_report()
        before["wall_clock_seconds"] = 10
        after["wall_clock_seconds"] = 20
        self.assertEqual(self.tool.fingerprint(before), self.tool.fingerprint(after))
        after["metrics"]["local_elements"]["completed"] = 199
        self.assertNotEqual(self.tool.fingerprint(before), self.tool.fingerprint(after))

    def test_ledger_events_change_determinism_fingerprint(self):
        before, after = passing_report(), passing_report()
        after["ledger"]["events"] = [{"kind": "illegal_grant", "amount": 10}]
        self.assertNotEqual(self.tool.fingerprint(before), self.tool.fingerprint(after))

    def test_invalid_config_rejected_before_any_artifacts(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp) / "trials"
            targets = copy.deepcopy(self.targets)
            targets["parameters"]["retort.base_hours"]["step"] = -1
            with self.assertRaises(ValueError):
                self.tool.calibrate({}, targets, out, 1, 2, lambda *_: 0)
            self.assertFalse(out.exists())

    def test_invalid_unselected_override_fails_before_launch(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp) / "trials"
            baseline = {"schema": 1, "name": "baseline", "base": "baseline", "overrides": {"ether.base_regen": -1}}
            with self.assertRaises(ValueError):
                self.tool.calibrate(baseline, self.targets, out, 1, 2, lambda *_: 0)
            self.assertFalse(out.exists())

    def test_missing_parameter_baseline_name_fails_before_launch(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp) / "trials"
            baseline = {"schema": 1, "base": "baseline", "overrides": {}}
            with self.assertRaises(ValueError):
                self.tool.calibrate(baseline, self.targets, out, 1, 2, lambda *_: 0)
            self.assertFalse(out.exists())

    def test_requested_seed_and_profile_are_binding(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp) / "trials"
            baseline = {"schema": 1, "name": "baseline", "base": "baseline", "overrides": {}}

            def wrong_seed(profile, seed, report):
                report.write_text(json.dumps(passing_report()))
                return 0

            result = self.tool.calibrate(baseline, self.targets, out, 99, 1, wrong_seed)
            self.assertEqual(result["stop_reason"], "calibration_invalid_contract")
            self.assertFalse((out / "candidate.json").exists())

    def test_invalid_later_trial_has_no_shipping_candidate(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp) / "trials"
            baseline = {"schema": 1, "name": "baseline", "base": "baseline", "overrides": {}}
            targets = copy.deepcopy(self.targets)
            targets["target"]["full_progression_seconds"]["min"] = 50000

            def backwards(profile, seed, report):
                result = passing_report()
                doc = json.loads(profile.read_text())
                result["profile"]["resolved_overrides"] = doc["overrides"]
                result["profile"]["name"] = doc["name"]
                if "trial-002" in str(report):
                    result["metrics"]["simulated_real_seconds"] = 25000
                    result["profile"]["hash"] = "c" * 64
                result["time"]["offline_seconds"] = result["metrics"]["simulated_real_seconds"] - result["time"]["active_seconds"]
                report.write_text(json.dumps(result))
                return 0

            result = self.tool.calibrate(baseline, targets, out, 1, 2, backwards)
            self.assertEqual(result["stop_reason"], "calibration_invalid_direction")
            self.assertFalse((out / "candidate.json").exists())

    def test_search_tightens_bracket_after_crossing_target_band(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp) / "trials"
            baseline = {"schema": 1, "name": "baseline", "base": "baseline", "overrides": {}}
            targets = copy.deepcopy(self.targets)
            targets["target"]["full_progression_seconds"] = {"min": 35000, "max": 36000}
            values = []

            def monotonic(profile, seed, report):
                doc = json.loads(profile.read_text())
                hours = doc["overrides"].get("retort.base_hours", 12)
                values.append(hours)
                result = passing_report()
                result["profile"]["name"] = doc["name"]
                result["profile"]["resolved_overrides"] = doc["overrides"]
                result["profile"]["hash"] = ("%064x" % hours)
                result["metrics"]["simulated_real_seconds"] = hours * 2500
                result["time"]["offline_seconds"] = result["metrics"]["simulated_real_seconds"] - result["time"]["active_seconds"]
                report.write_text(json.dumps(result))
                return 0

            self.tool.calibrate(baseline, targets, out, 1, 4, monotonic)
            self.assertEqual(values[:6], [12, 12, 18, 18, 15, 15])
            self.assertEqual(len(values[::2]), len(set(values[::2])))

    def test_changed_parameter_requires_changed_hash_and_stable_invariant_counters(self):
        for wrong_hash in (True, False):
            with tempfile.TemporaryDirectory() as temp:
                out = Path(temp) / "trials"
                baseline = {"schema": 1, "name": "baseline", "base": "baseline", "overrides": {}}
                targets = copy.deepcopy(self.targets)
                targets["target"]["full_progression_seconds"]["min"] = 40000

                def changed(profile, seed, report):
                    result = passing_report()
                    doc = json.loads(profile.read_text())
                    result["profile"]["name"] = doc["name"]
                    result["profile"]["resolved_overrides"] = doc["overrides"]
                    if "trial-002" in str(report):
                        result["metrics"]["simulated_real_seconds"] = 45000
                        if not wrong_hash:
                            result["profile"]["hash"] = "c" * 64
                            result["ledger"]["counters"]["sigils_crafted"] = 99
                    result["time"]["offline_seconds"] = result["metrics"]["simulated_real_seconds"] - result["time"]["active_seconds"]
                    report.write_text(json.dumps(result))
                    return 0

                result = self.tool.calibrate(baseline, targets, out, 1, 2, changed)
                self.assertTrue(result["stop_reason"].startswith("calibration_invalid"))
                self.assertFalse((out / "candidate.json").exists())

    def test_trials_preserved_and_repeats_verified(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp) / "trials"
            baseline = {"schema": 1, "name": "baseline", "base": "baseline", "overrides": {}}
            calls = []

            def run(profile, seed, report):
                calls.append(profile)
                result = passing_report()
                document = json.loads(profile.read_text())
                result["profile"]["name"] = document["name"]
                result["profile"]["resolved_overrides"] = document["overrides"]
                if "trial-002" in str(report):
                    result["profile"]["hash"] = "c" * 64
                    result["metrics"]["simulated_real_seconds"] = 45000
                result["time"]["offline_seconds"] = result["metrics"]["simulated_real_seconds"] - result["time"]["active_seconds"]
                report.write_text(json.dumps(result))
                return 0

            targets = copy.deepcopy(self.targets)
            targets["target"]["full_progression_seconds"]["min"] = 40000
            summary = self.tool.calibrate(baseline, targets, out, 1, 2, run)
            self.assertEqual(len(calls), 4)
            self.assertTrue((out / "trial-001" / "profile.json").exists())
            self.assertTrue((out / "trial-001" / "report.json").exists())
            self.assertTrue((out / "trial-001" / "repeat" / "report.json").exists())
            self.assertTrue((out / "trial-002" / "verdict.json").exists())
            self.assertIn(summary["stop_reason"], ["target_reached", "trial_limit", "parameter_bounds"])
            with self.assertRaises(FileExistsError):
                self.tool.calibrate(baseline, self.targets, out, 1, 2, run)


if __name__ == "__main__":
    unittest.main()
