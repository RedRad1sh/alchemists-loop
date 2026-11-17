import importlib.util
from pathlib import Path
import subprocess

import pytest


def exporter():
    path = Path(__file__).resolve().parents[3] / "alchemists-loop/tools/export_beta.py"
    assert path.is_file(), "Closed Beta needs an exporter that embeds its HTTPS configuration"
    spec = importlib.util.spec_from_file_location("export_beta", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.mark.parametrize("server", ["", "http://beta.invalid/api", "https://user:secret@beta.invalid/api"])
def test_beta_export_rejects_missing_or_insecure_server(tmp_path, server):
    module = exporter()
    project = tmp_path / "project"
    project.mkdir()
    config = project / "project.godot"
    config.write_text('[application]\nconfig/alchemy_server=""\n', encoding="utf-8")
    original = config.read_bytes()
    with pytest.raises(ValueError):
        module.export_beta(project, "unused-godot", server, tmp_path / "beta.apk")
    assert config.read_bytes() == original


@pytest.mark.parametrize("result", [0, 7])
def test_beta_export_embeds_server_and_restores_source(tmp_path, monkeypatch, result):
    module = exporter()
    project = tmp_path / "project"
    project.mkdir()
    config = project / "project.godot"
    original = b'[application]\nconfig/alchemy_server="https://ordinary.invalid/api"\nconfig/alchemy_store=""\n'
    config.write_bytes(original)
    output = tmp_path / "beta.apk"
    commands = []

    def run(command, **kwargs):
        commands.append(command)
        assert kwargs["shell"] is False
        embedded = config.read_text(encoding="utf-8")
        assert 'config/alchemy_server="https://beta.invalid/api"' in embedded
        assert 'config/alchemy_store=""' in embedded
        if result == 0:
            Path(command[-1]).write_bytes(b"test APK")
        return subprocess.CompletedProcess(command, result)

    monkeypatch.setattr(module.subprocess, "run", run)
    assert module.export_beta(project, "test-godot", "https://beta.invalid/api", output) == result
    assert commands[0][commands[0].index("--export-release") + 1] == "Closed Beta"
    assert config.read_bytes() == original
    assert output.exists() == (result == 0)


def test_beta_export_does_not_accept_previous_artifact(tmp_path, monkeypatch):
    module = exporter()
    project = tmp_path / "project"
    project.mkdir()
    config = project / "project.godot"
    original = b'[application]\nconfig/alchemy_server=""\n'
    config.write_bytes(original)
    output = tmp_path / "beta.apk"
    output.write_bytes(b"previous APK")
    monkeypatch.setattr(module.subprocess, "run", lambda command, **kwargs: subprocess.CompletedProcess(command, 0))
    with pytest.raises(RuntimeError, match="without a beta artifact"):
        module.export_beta(project, "test-godot", "https://beta.invalid/api", output)
    assert config.read_bytes() == original
    assert output.read_bytes() == b"previous APK"
