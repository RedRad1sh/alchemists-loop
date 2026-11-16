import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))


def load_tool():
    path = ROOT / "tools" / "render_progression_report.py"
    spec = importlib.util.spec_from_file_location("render_progression_report", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sample_report():
    return {
        "schema": 1,
        "seed": 7,
        "runner_commit": "abc123",
        "catalog_hash": "a" * 64,
        "profile": {"name": "baseline", "hash": "b" * 64, "base": "baseline", "resolved_overrides": {}},
        "time": {"active_seconds": 7200, "offline_seconds": 100800},
        "ledger": {
            "operation_count": 42,
            "counters": {
                "discoveries": 200,
                "brews": 20,
                "distillations": 248,
                "blends": 28,
                "sigils_crafted": 4,
                "prestige_count": 1,
            },
            "resources": {"ether_earned": 56811, "ether_spent": 56264},
            "events": [],
        },
        "phases": {
            name: {"state": "pass"}
            for name in [
                "bootstrap/catalog", "discovery", "idle", "retort", "sigil",
                "prestige", "post_prestige_discovery", "proof",
            ]
        },
        "metrics": {
            "local_elements": {"completed": 200, "total": 200},
            "recipes": {"completed": 196, "total": 196},
            "simulated_real_seconds": 108000,
            "active_player_seconds": 7200,
            "first_workshop_seconds": 500,
            "first_retort_seconds": 28800,
            "uncompleted_upgrades": 0,
            "uncompleted_sigil_targets": 0,
            "unexplained_resources": 0,
            "ether_deficit_at_completion": 0,
            "prestige_proof": True,
            "reload_proof": True,
            "replay_proof": True,
            "retort_queue_proof": True,
        },
        "verdict": "pass",
        "scope": {"balance_timing": "one feasible strategy, not a shortest-path lower bound"},
    }


class ProgressionReportTests(unittest.TestCase):
    def setUp(self):
        self.tool = load_tool()

    def test_render_contains_readable_dashboard_sections_and_calibration_summary(self):
        summary = {
            "baseline_profile_hash": "b" * 64,
            "best_profile_hash": "c" * 64,
            "accepted_trials": 2,
            "rejected_trials": 0,
            "stop_reason": "target_reached",
            "changed_parameters": {"ether.base_regen": 0.7, "retort.base_hours": 8},
            "trials": [
                {"trial": 1, "accepted": True, "objective": [0, 0, 0.2, 0], "reason": "trial_limit"},
                {"trial": 2, "accepted": True, "objective": [0, 0, 0, 1], "reason": "target_reached"},
            ],
        }
        html = self.tool.render_report(sample_report(), summary)

        for text in [
            "Alchemist’s Loop",
            "ПОЛНЫЙ ПРОГОН",
            "Виртуальное время",
            "Активное время игрока",
            "Offline idle",
            "Фазы прогрессии",
            "Покрытие каталога",
            "Retort",
            "Калибровка",
            "target_reached",
            "ether.base_regen",
            "200 / 200",
            "196 / 196",
        ]:
            self.assertTrue(text in html, text.encode("unicode_escape").decode("ascii"))
        self.assertIn("--violet", html)
        self.assertNotIn("<link", html)
        self.assertNotIn("https://", html)

    def test_render_escapes_report_values(self):
        report = sample_report()
        report["scope"]["balance_timing"] = "<script>alert('x')</script> & unsafe"
        report["profile"]["name"] = '"quoted"'
        html = self.tool.render_report(report)

        self.assertNotIn("<script>alert", html)
        self.assertIn("&lt;script&gt;alert(&#x27;", html)
        self.assertIn("&quot;quoted&quot;", html)

    def test_write_report_creates_standalone_utf8_html(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "progression.html"
            result = self.tool.write_report(output, sample_report())
            self.assertEqual(result, output)
            content = output.read_text(encoding="utf-8")
            self.assertTrue(content.startswith("<!doctype html>"))
            self.assertGreater(len(content), 10000)
            self.assertEqual(output.suffix, ".html")


def sample_scenario_report():
    origin = 1794614400.0
    before = {
        "local_discovered_count": 4,
        "local_discovered_ids": ["earth", "fire", "water", "wind"],
        "ether_available": 100, "ether_cap": 180, "gold": 0, "known_recipe_count": 3,
        "inventory": {"fire": 2, "water": 2, "earth": 1, "wind": 1},
        "workshop": {"rank": 0, "autonomy": 0, "xp": 0},
        "upgrade_levels": {"items": {}, "spring": {"speed": 0}, "mastery": 0},
        "retort": {"essences": {}},
        "clock": {"now": origin, "active_seconds": 0, "offline_seconds": 0, "simulated_real_seconds": 0},
    }
    after = {
        "local_discovered_count": 5,
        "local_discovered_ids": ["clay", "earth", "fire", "water", "wind"],
        "ether_available": 180, "ether_cap": 180, "gold": 0, "known_recipe_count": 4,
        "inventory": {"fire": 1, "water": 2, "earth": 1, "wind": 1, "clay": 2},
        "workshop": {"rank": 0, "autonomy": 0, "xp": 12},
        "upgrade_levels": {"items": {"ether_cap": 1}, "spring": {"speed": 0}, "mastery": 0},
        "retort": {"essences": {}},
        "clock": {"now": origin + 21600, "active_seconds": 3600, "offline_seconds": 18000, "simulated_real_seconds": 21600},
    }
    active_segment = {
        "kind": "active", "seconds": 3600.0,
        "before": before, "after": after,
        "delta": {"ether_available": 0, "inventory": {"clay": 2, "fire": -1}, "workshop": {"xp": 12}},
        "clock_delta": {"active_seconds": 3600.0},
        "events": [
            {"kind": "discovery", "output": "clay", "at": origin + 120},
            {"kind": "upgrade", "upgrade": "ether_cap", "level": 1, "at": origin + 200},
        ],
        "counters": {"discoveries": 1, "upgrade_purchases": 1},
        "new_elements": ["clay"], "new_unlocks": ["bench"],
        "stalls": [], "ledger": {"unexplained_resources": [], "events": []},
        "offline_granted": {}, "offline_spent": {}, "production": {},
        "available_goals": [], "blocked_goals": [],
    }
    offline_segment = {
        "kind": "offline", "seconds": 18000.0,
        "before": after, "after": after,
        "delta": {"ether_available": 80},
        "clock_delta": {"offline_seconds": 18000.0},
        "events": [{"kind": "offline_replay", "at": origin + 21600}],
        "counters": {"offline_simulated_seconds": 18000.0},
        "new_elements": [], "new_unlocks": [],
        "stalls": [], "ledger": {"unexplained_resources": [], "events": []},
        "offline_granted": {"ether": 80, "spring_items": 6, "inventory": {}, "essences": {}},
        "offline_spent": {"ether": 0, "inventory": {}},
        "production": {"saved": True, "ether_gained": 80, "ether_spent": 0, "spring_items": 6,
                       "skipped_seconds": 0, "retort": {"collected": 0, "essences": {}}},
        "available_goals": [], "blocked_goals": [],
    }
    goals = [
        {"id": "discovery/steam", "kind": "discovery", "available": True, "reason": "available", "missing": {}},
        {"id": "upgrade/ether_regen", "kind": "upgrade", "available": False, "reason": "ether", "missing": {"ether": 45}},
    ]
    return {
        "schema": 1, "scenario": 1, "scenario_name": "1h-active-5h-offline-1h-active",
        "seed": 31, "runner_commit": "working-tree", "catalog_hash": "a" * 64,
        "profile": {"name": "baseline", "hash": "b" * 64, "base": "baseline", "schema": 1, "resolved_overrides": {}},
        "definition": {"scenario": 1, "segments": [{"kind": "active", "seconds": 3600.0}, {"kind": "offline", "seconds": 18000.0}]},
        "item_names": {"clay": "Глина", "fire": "Огонь", "steam": "Пар"},
        "before": before, "after": after,
        "delta": {"ether_available": 80, "local_discovered_count": 1, "known_recipe_count": 1,
                  "inventory": {"clay": 2, "fire": -1}, "workshop": {"xp": 12}},
        "segments": [active_segment, offline_segment],
        "time": {"active_seconds": 3600, "offline_seconds": 18000, "simulated_real_seconds": 21600},
        "available_goals": goals, "blocked_goals": [goals[1]],
        "session": {"policy": "session_balanced", "counters": {"discoveries": 1, "upgrade_purchases": 1, "brews": 0},
                    "events": active_segment["events"], "stalls": []},
        "scope": {"policy": "Deterministic recipe-aware strategy", "sigils": "Four local fixture offers",
                  "time": "Virtual elapsed active/offline time"},
        "errors": [], "verdict": "pass",
    }


def sample_comparison():
    first = sample_scenario_report()
    second = sample_scenario_report()
    second["profile"] = dict(first["profile"], name="fast")
    second["after"] = dict(first["after"], local_discovered_count=6, ether_available=260)
    metrics = []
    for index, report in enumerate((first, second)):
        row = {
            "profile": report["profile"]["name"],
            "local_elements": report["after"]["local_discovered_count"],
            "new_elements": 1 + index,
            "ether_available": report["after"]["ether_available"],
            "upgrade_purchases": 1 + 2 * index,
            "offline_ether_earned": 80 + 100 * index,
            "offline_ether_spent": 0,
            "offline_spring_items": 6 + 6 * index,
            "first_unlock_seconds": {"clay": 120},
            "first_upgrade_seconds": {"ether_cap": 200},
            "blockers": report["blocked_goals"],
            "final_delta": report["delta"],
            "segments": [{"kind": s["kind"], "delta": s["delta"], "offline_granted": s["offline_granted"]} for s in report["segments"]],
        }
        metrics.append(row)
    for row in metrics:
        row["vs_first"] = {k: row[k] - metrics[0][k] for k in ("local_elements", "new_elements", "ether_available", "upgrade_purchases", "offline_ether_earned")}
    return {"schema": 1, "comparison": 1, "reports": [first, second], "metrics": metrics, "verdict": "pass"}


class ScenarioReportTests(unittest.TestCase):
    def setUp(self):
        self.tool = load_tool()

    def test_scenario_report_renders_player_session_sections(self):
        html = self.tool.render_report(sample_scenario_report())
        for text in [
            "СЕССИЯ ИГРОКА",
            "1h-active-5h-offline-1h-active",
            "Активная игра",
            "Offline-сессия",
            "Хронология сессии",
            "Было", "Стало", "Δ",
            "Глина",
            "ether_cap",
            "не хватает эфира",
            "Offline-производство",
            "Доступные следующие шаги",
            "PASS",
            "baseline",
        ]:
            self.assertTrue(text in html, text.encode("unicode_escape").decode("ascii"))
        self.assertNotIn("<link", html)
        self.assertNotIn("https://", html)

    def test_scenario_delta_signs_are_explicit(self):
        html = self.tool.render_report(sample_scenario_report())
        self.assertIn("+80", html)
        self.assertIn("-1", html)
        self.assertIn("+2", html)

    def test_scenario_escapes_element_and_goal_names(self):
        report = sample_scenario_report()
        report["item_names"]["clay"] = "<script>alert('x')</script>"
        report["available_goals"][0]["id"] = 'discovery/"quoted"'
        report["scenario_name"] = "<b>unsafe</b>"
        html = self.tool.render_report(report)
        self.assertNotIn("<script>alert", html)
        self.assertIn("&lt;script&gt;alert(&#x27;", html)
        self.assertIn("&quot;quoted&quot;", html)
        self.assertNotIn("<b>unsafe</b>", html)

    def test_comparison_renders_profile_table_and_diffs(self):
        html = self.tool.render_report(sample_comparison())
        for text in [
            "СРАВНЕНИЕ БАЛАНСОВ",
            "baseline", "fast",
            "Открыто элементов",
            "Новые элементы",
            "Эфир в конце",
            "Куплено улучшений",
            "Эфир за offline",
            "+1", "+80", "+2",
            "PASS",
        ]:
            self.assertTrue(text in html, text.encode("unicode_escape").decode("ascii"))
        self.assertNotIn("<link", html)
        self.assertNotIn("https://", html)

    def test_comparison_incomplete_verdict_is_visible(self):
        comparison = sample_comparison()
        comparison["verdict"] = "incomplete"
        comparison["reports"][1]["verdict"] = "incomplete"
        html = self.tool.render_report(comparison)
        self.assertIn("INCOMPLETE", html)

    def test_aggregate_report_still_renders_pipeline(self):
        html = self.tool.render_report(sample_report())
        self.assertIn("ПОЛНЫЙ ПРОГОН", html)
        self.assertIn("Фазы прогрессии", html)
        self.assertNotIn("СЕССИЯ ИГРОКА", html)


if __name__ == "__main__":
    unittest.main()
