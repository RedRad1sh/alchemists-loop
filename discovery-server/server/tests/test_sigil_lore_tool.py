"""Regression tests for lore artifact writer and drift checks."""
import importlib.util
import json
from pathlib import Path

TOOL = Path(__file__).resolve().parents[3] / "alchemists-loop/tools/gen_sigil_lore.py"
spec = importlib.util.spec_from_file_location("sigil_lore_tool", TOOL)
lore = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lore)


def test_elements_command_writes_missing_file(tmp_path, monkeypatch):
    output = tmp_path / "elements.json"
    monkeypatch.setattr(lore, "ELEMENTS_PATH", output)
    assert lore.main(["elements"]) == 0
    assert lore.main(["elements", "--check"]) == 0
    assert json.loads(output.read_text()) == json.loads(
        (lore.TOOLS_DIR / "sigil_elements_source.json").read_text())


def test_fragment_check_detects_text_only_drift(tmp_path):
    lore.write_fragments(tmp_path)
    assert lore.check_fragments(tmp_path) == 0
    path = tmp_path / "actions.json"
    payload = json.loads(path.read_text())
    payload["fragments"][0]["text"] += " тихо"
    path.write_text(json.dumps(payload, ensure_ascii=False))
    assert lore.check_fragments(tmp_path) == 1
