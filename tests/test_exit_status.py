"""Exit status contract: compile a .du program, run the native binary, assert its status."""

import subprocess
from pathlib import Path

ROOT = Path(__file__).parent.parent
DUENDE = ROOT / "duende"
EXAMPLES = ROOT / "examples"
BUILD = EXAMPLES / "duende_build"


def duende(*args):
    return subprocess.run([str(DUENDE), *args], cwd=ROOT, capture_output=True, text=True)


def test_native_binary_returns_main_status():
    exe = BUILD / "exit_status"
    exe.unlink(missing_ok=True)
    res = duende(str(EXAMPLES / "exit_status.du"))
    assert res.returncode == 0, res.stdout + res.stderr
    run = subprocess.run([str(exe)], capture_output=True, text=True)
    assert run.returncode == 23
    assert run.stdout == "checks failed: 23\n"


def test_run_flag_propagates_program_status():
    res = duende("-r", str(EXAMPLES / "exit_status.du"))
    assert res.returncode == 23, res.stdout + res.stderr
    assert res.stdout == "checks failed: 23\n"


def test_run_flag_propagates_program_status_when_verbose():
    res = duende("-r", "-v", str(EXAMPLES / "exit_status.du"))
    assert res.returncode == 23, res.stdout + res.stderr
    assert "checks failed: 23\n" in res.stdout
    assert "Program exited with code: 23" in res.stdout


def test_run_flag_returns_zero_for_successful_program():
    res = duende("-r", str(EXAMPLES / "variables.du"))
    assert res.returncode == 0, res.stdout + res.stderr
    assert res.stdout.strip() == "55"
