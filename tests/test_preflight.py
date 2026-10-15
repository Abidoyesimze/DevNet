"""Tests for scripts/preflight.py.

Runs the script as a subprocess so we test the real exit-code behaviour,
including the case where a required binary is absent from PATH.
"""
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PREFLIGHT = REPO_ROOT / "scripts" / "preflight.py"


def _run(extra_env: dict | None = None, args: list[str] | None = None) -> subprocess.CompletedProcess:
    env = {**os.environ, **(extra_env or {})}
    cmd = [sys.executable, str(PREFLIGHT)] + (args or [])
    return subprocess.run(cmd, capture_output=True, text=True, env=env)


class TestMissingBinaries:
    def test_missing_forge_exits_nonzero(self, tmp_path):
        """Exit 1 when forge/anvil are not on PATH."""
        result = _run(extra_env={"PATH": str(tmp_path)})
        assert result.returncode != 0

    def test_missing_forge_prints_missing_tag(self, tmp_path):
        result = _run(extra_env={"PATH": str(tmp_path)})
        assert "[MISSING]" in result.stdout

    def test_missing_forge_mentions_foundry(self, tmp_path):
        result = _run(extra_env={"PATH": str(tmp_path)})
        assert "foundryup" in result.stdout.lower() or "foundry" in result.stdout.lower()


class TestHappyPath:
    def test_exits_zero_when_forge_present(self):
        """Smoke test: exits 0 in a working dev environment."""
        result = _run()
        # If forge/anvil are present and Python >= 3.12 (which it must be to run
        # the test suite), this should exit 0.  A missing optional package is only
        # a WARN and must not cause a non-zero exit.
        assert result.returncode == 0, (
            f"preflight.py exited {result.returncode}.\nstdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )

    def test_all_required_checks_passed_message(self):
        result = _run()
        if result.returncode == 0:
            assert "All required checks passed" in result.stdout
