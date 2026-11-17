import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import urlsplit


def export_beta(project: Path, godot: str, server: str, output: Path) -> int:
    server = server.strip().rstrip("/")
    url = urlsplit(server)
    if url.scheme != "https" or not url.hostname or url.username or url.password or url.query or url.fragment:
        raise ValueError("Closed Beta requires an explicit HTTPS API URL without credentials, query or fragment")
    project = project.resolve()
    output = output.resolve()
    config = project / "project.godot"
    original = config.read_bytes()
    text = original.decode("utf-8")
    setting = "config/alchemy_server=" + json.dumps(server, ensure_ascii=False)
    pattern = r"(?m)^config/alchemy_server=.*$"
    if re.search(pattern, text):
        configured = re.sub(pattern, lambda _: setting, text)
    elif "[application]" in text:
        configured = text.replace("[application]", "[application]\n" + setting, 1)
    else:
        raise ValueError("project.godot has no application section")
    output.parent.mkdir(parents=True, exist_ok=True)
    try:
        config.write_text(configured, encoding="utf-8", newline="")
        with tempfile.TemporaryDirectory(prefix=".beta-export-", dir=output.parent) as staging:
            artifact = Path(staging) / output.name
            result = subprocess.run([
                godot, "--headless", "--path", str(project), "--export-release", "Closed Beta", str(artifact),
            ], check=False)
            if result.returncode == 0:
                if not artifact.is_file() or artifact.stat().st_size == 0:
                    raise RuntimeError("Godot returned success without a beta artifact")
                artifact.replace(output)
            return result.returncode
    finally:
        config.write_bytes(original)


def main() -> int:
    parser = argparse.ArgumentParser(description="Export Closed Beta with its HTTPS server embedded")
    parser.add_argument("--server", required=True)
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    try:
        return export_beta(project, args.godot, args.server, args.output or project / "build/alchemists-loop-beta.apk")
    except (OSError, ValueError, RuntimeError) as exc:
        parser.exit(1, str(exc) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
