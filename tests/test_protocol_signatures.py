"""Protocol conformance checks exercise native compile/run and rejection paths."""

import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).parent.parent
COMPILER = ROOT / "duende"
EXAMPLES = ROOT / "examples"


def compile_program(name):
    source = EXAMPLES / f"{name}.du"
    return subprocess.run([str(COMPILER), str(source)], cwd=ROOT,
                          capture_output=True, text=True, timeout=60), source


def test_local_and_imported_protocol_signatures_dispatch():
    compiled, source = compile_program("protocol_signatures")
    assert compiled.returncode == 0, compiled.stdout + compiled.stderr
    binary = source.parent / "duende_build" / source.stem
    ran = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
    assert ran.returncode == 0, ran.stderr
    assert ran.stdout.splitlines() == ["2", "local", "2", "value", "9", "library", "4"]


@pytest.mark.parametrize(("name", "diagnostic"), [
    ("protocol_cases/errors/bad_nested_argument", "parameter 'values' type does not match protocol"),
    ("protocol_cases/errors/bad_return", "return type does not match protocol"),
    ("protocol_cases/errors/bad_parameter_name", "parameter 1 name does not match protocol"),
    ("protocol_cases/errors/bad_default", "parameter 'value' default does not match protocol"),
    ("protocol_cases/errors/bad_imported_nested_argument", "parameter 'values' type does not match protocol"),
    ("protocol_cases/errors/mutating_let_receiver", "Cannot call mutating method 'increment' on let binding 'counter'"),
])
def test_incompatible_protocol_signature_is_a_duende_error(name, diagnostic):
    compiled, source = compile_program(name)
    output = compiled.stdout + compiled.stderr
    assert compiled.returncode == 1, output
    assert diagnostic in output, output
    assert "Semantic validation failed" in output, output
    assert "dmd compilation failed" not in output, output
    assert not (source.parent / "duende_build" / source.stem).exists()
