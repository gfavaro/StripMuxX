#!/usr/bin/env python3
"""Install the opt-in Git pre-push test gate without replacing existing hooks."""
from pathlib import Path
import os
import subprocess
import sys

def install(root: Path) -> Path:
    git_dir = Path(subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "--absolute-git-dir"], text=True
    ).strip())
    current_hooks = subprocess.check_output(
        ["git", "-C", str(root), "config", "--get", "core.hooksPath"], text=True,
        stderr=subprocess.DEVNULL
    ) if subprocess.run(["git", "-C", str(root), "config", "--get", "core.hooksPath"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0 else ""
    if current_hooks.strip():
        raise RuntimeError("Existing core.hooksPath is configured; leaving it untouched. Add script/hooks/pre-push to that hook manually.")
    target = git_dir / "hooks" / "pre-push"
    if target.exists() or target.is_symlink():
        raise RuntimeError(f"Existing pre-push hook at {target}; leaving it untouched.")
    source = root / "script" / "hooks" / "pre-push"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(source.read_bytes())
    os.chmod(target, 0o755)
    return target

if __name__ == "__main__":
    try:
        print(f"Installed pre-push gate: {install(Path(__file__).resolve().parent.parent)}")
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
