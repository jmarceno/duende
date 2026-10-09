"""Typed module interfaces: nested types, identity, visibility, and cycles."""
from pathlib import Path
import subprocess

import pytest

ROOT = Path(__file__).parent.parent
COMPILER = ROOT / "duende"


def compile_program(source):
    return subprocess.run([str(COMPILER), str(source)], cwd=ROOT,
                          capture_output=True, text=True, timeout=60)


def run_program(source):
    compiled = compile_program(source)
    assert compiled.returncode == 0, compiled.stdout + compiled.stderr
    binary = source.parent / "duende_build" / source.stem
    ran = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
    assert ran.returncode == 0, ran.stderr
    return ran.stdout.splitlines()


@pytest.mark.parametrize("name, expected", [
    ("iface_cases/nested/use_nested", ["2", "5", "8", "9"]),
    ("iface_cases/same_name/use_same", ["1", "4"]),
    ("iface_cases/visibility/use_shown", ["7"]),
    ("iface_cases/cycle_ok/use_cycle", ["1", "2", "2", "1"]),
    ("iface_cases/named/use_named", ["6", "16", "16"]),
])
def test_module_interface_program(name, expected):
    source = ROOT / "examples" / (name + ".du")
    assert run_program(source) == expected


@pytest.mark.parametrize("name, diagnostic", [
    ("iface_cases/nested/bad_nested", "Initializer type does not match"),
    ("iface_cases/same_name/bad_same", "Initializer type does not match"),
    ("iface_cases/assign/bad_let", "Cannot assign to let binding 'fixed'"),
    ("iface_cases/assign/bad_value", "Assigned expression type does not match variable 'counter'"),
    ("iface_cases/assign/bad_arg", "Argument type mismatch for parameter 'n'"),
    ("iface_cases/visibility/use_hidden", "has no public symbol 'hidden'"),
    ("iface_cases/cycle/use_cycle", "Cannot infer the type of 'x' across an import cycle"),
])
def test_module_interface_rejected(name, diagnostic):
    source = ROOT / "examples" / (name + ".du")
    compiled = compile_program(source)
    output = compiled.stdout + compiled.stderr
    assert compiled.returncode == 1, output
    assert diagnostic in output, output
    assert "Semantic validation failed" in output, output
    assert "dmd compilation failed" not in output, output
    assert not (source.parent / "duende_build" / source.stem).exists()
