import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))


def sample_scenario_report():
    before = {"inventory": {"fire": 5}, "ether": 100, "ether_overflow": 0,
              "ether_available": 100, "ether_cap": 180, "local_discovered_ids": ["fire"],
              "local_discovered_count": 1, "known_recipe_count": 0, "upgrade_levels": {},
              "workshop": {}, "retort": {"essences": {}}, "sigils": {}, "gold": 0,
              "clock": {"now": 1000, "active_seconds": 0, "offline_seconds": 0,
                        "simulated_real_seconds": 0, "active_player_seconds": 0}}
    after = copy.deepcopy(before)
    after["ether"] = after["ether_available"] = 180
    after["clock"].update(now=19000, offline_seconds=18000, simulated_real_seconds=18000)
    delta = {"ether": 80, "ether_available": 80, "clock": {"now": 18000, "offline_seconds": 18000, "simulated_real_seconds": 18000}}
    return {"schema": 1, "scenario": 1, "scenario_name": "test", "seed": 31,
            "catalog_hash": "a" * 64, "runner_commit": "working-tree", "item_names": {},
            "profile": {"schema": 1, "name": "baseline", "base": "baseline", "hash": "b" * 64, "resolved_overrides": {}},
            "definition": {"scenario": 1, "segments": [{"kind": "offline", "seconds": 18000}]},
            "before": before, "after": after, "delta": delta, "time": after["clock"],
            "available_goals": [], "blocked_goals": [], "errors": [], "session": {"events": [], "counters": {}},
            "verdict": "pass", "state": "complete", "segments": [
                {"kind": "offline", "seconds": 18000, "before": before, "after": after, "delta": delta,
                 "clock_delta": delta["clock"], "events": [], "counters": {}, "stalls": [], "policy": "production_offline",
                 "reason": "", "blocked_goals": [], "available_goals": [], "new_elements": [], "new_unlocks": [],
                 "offline_granted": {"ether": 80}, "offline_spent": {"ether": 0}, "production": {"saved": True},
                 "ledger": {"operation_count": 1, "events": [{"kind": "save_offline_replay", "deltas": {"ether": 80, "reserve": 0, "inventory": {}, "essences": {}}}], "unexplained_resources": []}}]}


class ScenarioLauncherTests(unittest.TestCase):
    def setUp(self):
        path = ROOT / "tools/run_player_scenario.py"
        self.assertTrue(path.exists(), "scenario launcher missing")
        spec = importlib.util.spec_from_file_location("run_player_scenario", path)
        self.tool = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.tool)

    def test_arguments_preserve_scenario_profile_seed_and_progress(self):
        command = self.tool.build_command(Path("scenario.json"), Path("profile.json"), 31, Path("out.json"), "godot")
        self.assertIn("res://tests/progression_runner.tscn", command)
        self.assertIn("--selftest", command)
        self.assertIn("--seed=31", command)
        self.assertTrue(any(v.startswith("--scenario=") and v.endswith("scenario.json") for v in command))
        self.assertTrue(any(v.startswith("--progress=") for v in command))

    def test_validation_rejects_false_pass_time_resources_and_unexplained(self):
        report = sample_scenario_report()
        self.assertEqual(self.tool.validate_report(report), [])
        for mutate in [lambda r: r["time"].update(offline_seconds=0),
                       lambda r: r["segments"][0]["clock_delta"].update(offline_seconds=18001),
                       lambda r: r["after"]["inventory"].update(fire=-1),
                       lambda r: r["segments"][0]["ledger"]["unexplained_resources"].append("grant"),
                       lambda r: r["segments"][0]["delta"].update(ether=99),
                       lambda r: r["segments"][0]["ledger"]["events"][0]["deltas"].update(ether=99),
                       lambda r: r.update(catalog_hash="wrong")]:
            bad = copy.deepcopy(report)
            mutate(bad)
            self.assertTrue(self.tool.validate_report(bad))

    def test_validation_rejects_free_text_goal_reasons(self):
        report = sample_scenario_report()
        goal = {"id": "workshop/rank/1", "kind": "workshop_rank", "available": False,
                "missing": {"requirement": "Не хватает Кирпич: нужно ×20."},
                "reason": "Не хватает Кирпич: нужно ×20."}
        report["available_goals"] = [goal]
        report["blocked_goals"] = [copy.deepcopy(goal)]
        errors = self.tool.validate_report(report)
        self.assertTrue(any("reason" in error for error in errors), errors)
        report["available_goals"] = []
        report["blocked_goals"] = []
        self.assertEqual(self.tool.validate_report(report), [])

    def test_comparison_keeps_profile_order_and_concrete_session_yield(self):
        first = sample_scenario_report()
        second = copy.deepcopy(first)
        second["profile"]["name"] = "fast"
        result = self.tool.compare_reports([first, second])
        self.assertEqual([r["profile"]["name"] for r in result["reports"]], ["baseline", "fast"])
        self.assertEqual(result["metrics"][0]["offline_ether_earned"], 80)
        self.assertEqual(result["metrics"][0]["segments"][0]["delta"]["ether"], 80)
        self.assertIn("vs_first", result["metrics"][1])

    def test_profiles_execute_sequentially_and_incomplete_propagates(self):
        order = []
        def run(profile, seed, scenario, report, godot=None, timeout=120):
            order.append(Path(profile).stem)
            data = sample_scenario_report()
            data["profile"]["name"] = Path(profile).stem
            if len(order) == 2:
                data["verdict"] = "incomplete"
            Path(report).write_text(json.dumps(data), encoding="utf-8")
            return 0 if len(order) == 1 else 2
        with tempfile.TemporaryDirectory() as temp, patch.object(self.tool, "run_profile", side_effect=run):
            result = self.tool.run_profiles([Path("baseline.json"), Path("slow.json")], 31, Path("scenario.json"), Path(temp))
            self.assertNotEqual(result, 0)
            self.assertEqual(order, ["baseline", "slow"])
            comparison = json.loads((Path(temp) / "comparison.json").read_text(encoding="utf-8"))
            self.assertEqual(comparison["verdict"], "incomplete")

    def test_report_metrics_expose_player_actions_board_rewards_and_cap_sources(self):
        report = sample_scenario_report()
        report["before"]["ether_cap"] = 180
        report["after"]["ether_cap"] = 190
        report["session"]["counters"] = {
            "player_action_seconds": 12.0,
            "active_simulated_seconds": 600.0,
            "contract_claims": 1,
            "achievement_updates": 2,
        }
        report["segments"][0]["events"] = [{
            "kind": "contract_claim",
            "materials": {"brick": 3},
            "buff": "spring_yield",
            "decor": "planetarium_ember",
        }]
        report["segments"][0]["ledger"]["events"].append({
            "kind": "contract_claim:daily:vein:bronze:day",
            "deltas": {"ether": 0, "reserve": 0, "inventory": {"brick": 3}, "essences": {}},
            "ether_cap_delta": 0,
        })
        report["segments"][0]["ledger"]["events"].append({
            "kind": "ether_purchase:ether_cap",
            "deltas": {"ether": -70, "reserve": 0, "inventory": {}, "essences": {}},
            "ether_cap_delta": 10,
            "achievement_ids": ["items/5"],
            "achievement_cap_delta": 10,
        })
        metrics = self.tool.report_metrics(report)
        self.assertEqual(metrics["player_action_seconds"], 12.0)
        self.assertEqual(metrics["active_simulated_seconds"], 600.0)
        self.assertEqual(metrics["contract_claims"], 1)
        self.assertEqual(metrics["achievement_updates"], 2)
        self.assertEqual(metrics["board_materials"], {"brick": 3})
        self.assertEqual(metrics["board_buffs"], {"spring_yield": 1})
        self.assertEqual(metrics["board_decor"], {"planetarium_ember": 1})
        self.assertEqual(metrics["ether_cap_delta"], 10)
        self.assertEqual(metrics["achievement_cap_delta"], 10)
        self.assertEqual(metrics["contract_cap_delta"], 0)

    def test_fingerprint_ignores_wall_clock_only(self):
        report = sample_scenario_report()
        same = copy.deepcopy(report)
        same["wall_clock_seconds"] = 99
        self.assertEqual(self.tool.fingerprint(report), self.tool.fingerprint(same))
        same["after"]["ether"] -= 1
        self.assertNotEqual(self.tool.fingerprint(report), self.tool.fingerprint(same))


if __name__ == "__main__":
    unittest.main()
