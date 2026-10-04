"""Exit status contract: compile a .du program, run the native binary, assert its status."""

import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).parent.parent
DUENDE = ROOT / "duende"
EXAMPLES = ROOT / "examples"
BUILD = EXAMPLES / "duende_build"


def duende(*args):
    return subprocess.run([str(DUENDE), *args], cwd=ROOT, capture_output=True, text=True)


def private_copy(example, name):
    """Copy an example under a unique name so parallel tests never share build products."""
    BUILD.mkdir(parents=True, exist_ok=True)
    dst = BUILD / f"{name}.du"
    shutil.copyfile(EXAMPLES / example, dst)
    return dst


def test_native_binary_returns_main_status():
    src = private_copy("exit_status.du", "exit_status_direct")
    exe = src.parent / "duende_build" / src.stem
    exe.unlink(missing_ok=True)
    res = duende(str(src))
    assert res.returncode == 0, res.stdout + res.stderr
    run = subprocess.run([str(exe)], capture_output=True, text=True)
    assert run.returncode == 23
    assert run.stdout == "checks failed: 23\n"


def test_run_flag_propagates_program_status():
    res = duende("-r", str(private_copy("exit_status.du", "exit_status_run")))
    assert res.returncode == 23, res.stdout + res.stderr
    assert res.stdout == "checks failed: 23\n"


def test_run_flag_propagates_program_status_when_verbose():
    res = duende("-r", "-v", str(private_copy("exit_status.du", "exit_status_verbose")))
    assert res.returncode == 23, res.stdout + res.stderr
    assert "checks failed: 23\n" in res.stdout
    assert "Program exited with code: 23" in res.stdout


def test_run_flag_returns_zero_for_successful_program():
    res = duende("-r", str(private_copy("variables.du", "variables_run")))
    assert res.returncode == 0, res.stdout + res.stderr
    assert res.stdout.strip() == "55"
