"""Builtin signatures, shadowing, and the unresolved-provider boundary."""
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
    ("builtin_cases/calls", ["2", "3", "text", "lines", "2", "2", "5", "1", "2", "false", "2", "4"]),
    ("builtin_cases/shadow_fn", ["7"]),
    ("builtin_cases/shadow_value", ["3"]),
    ("builtin_cases/shadow_lambda", ["11"]),
    ("builtin_cases/shadow/use_abs", ["9"]),
])
def test_builtin_program(name, expected):
    source = ROOT / "examples" / (name + ".du")
    assert run_program(source) == expected


@pytest.mark.parametrize("name, diagnostic", [
    ("builtin_cases/errors/bad_arity", "Missing argument for parameter 'value' in call to 'len'"),
    ("builtin_cases/errors/bad_type", "Argument type mismatch for parameter 'value' in call to 'len'"),
    ("builtin_cases/errors/bad_nested", "Argument type mismatch for parameter 'value' in call to 'len'"),
    ("builtin_cases/errors/bad_list", "List element type does not match"),
    ("builtin_cases/errors/bad_assign", "Initializer type does not match"),
    ("builtin_cases/errors/bad_nested_result", "Initializer type does not match"),
    ("builtin_cases/errors/bad_shadow", "'len' is not a function"),
])
def test_builtin_rejected(name, diagnostic):
    source = ROOT / "examples" / (name + ".du")
    compiled = compile_program(source)
    output = compiled.stdout + compiled.stderr
    assert compiled.returncode == 1, output
    assert diagnostic in output, output
    assert "Semantic validation failed" in output, output
    assert "dmd compilation failed" not in output, output
    assert not (source.parent / "duende_build" / source.stem).exists()


def test_unknown_provider_has_no_builtin_signature():
    # Provider signature checking is DU-12. This name must reach the D compiler
    # instead of being rejected as a malformed builtin.
    source = ROOT / "examples" / "builtin_cases" / "errors" / "bad_provider.du"
    compiled = compile_program(source)
    output = compiled.stdout + compiled.stderr
    assert compiled.returncode != 0, output
    assert "Semantic validation failed" not in output, output
    assert "Argument type mismatch" not in output, output
    assert "dmd compilation failed" in output, output
