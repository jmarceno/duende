"""Imported calls, provider signatures, and method/constructor/field contracts."""
from pathlib import Path
import subprocess

import pytest

ROOT = Path(__file__).parent.parent
COMPILER = ROOT / "duende"

CALL_OK = ["14", "err", "4", "0", "7"]


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


def assert_rejected(source, diagnostics):
    compiled = compile_program(source)
    output = compiled.stdout + compiled.stderr
    assert compiled.returncode == 1, output
    for diagnostic in diagnostics:
        assert diagnostic in output, output
    assert "Semantic validation failed" in output, output
    assert "dmd compilation failed" not in output, output
    assert not (source.parent / "duende_build" / source.stem).exists()


@pytest.mark.parametrize("name", [
    "iface_cases/calls/use_module",
    "iface_cases/calls/use_selective",
    "iface_cases/calls/use_wildcard",
    "iface_cases/calls/use_reexport",
])
def test_imported_call_accepts_context(name):
    source = ROOT / "examples" / (name + ".du")
    assert run_program(source) == CALL_OK


def test_imported_named_arguments_evaluate_once():
    source = ROOT / "examples" / "iface_cases" / "calls" / "use_order.du"
    assert run_program(source) == ["14", "ca"]


@pytest.mark.parametrize("name", [
    "iface_cases/calls/bad_module",
    "iface_cases/calls/bad_selective",
    "iface_cases/calls/bad_wildcard",
    "iface_cases/calls/bad_reexport",
])
def test_imported_call_rejects_bad_arguments(name):
    source = ROOT / "examples" / (name + ".du")
    assert_rejected(source, [
        "Unknown named parameter 'z' for function 'add3'",
        "Duplicate argument for parameter 'a' in call to 'add3'",
        "Too many arguments in call to 'add3'",
        "Missing argument for parameter 'a' in call to 'add3'",
        "List element type does not match",
    ])


@pytest.mark.parametrize("name, expected", [
    ("provider_cases/use_checked", ["6", "20", "no", "8", "hi"]),
    ("provider_cases/use_selective", ["6", "no"]),
    ("provider_cases/use_wildcard", ["6", "hi"]),
])
def test_checked_provider(name, expected):
    source = ROOT / "examples" / (name + ".du")
    assert run_program(source) == expected


def test_checked_provider_rejects_bad_arguments():
    source = ROOT / "examples" / "provider_cases" / "bad_checked.du"
    assert_rejected(source, [
        "Too many arguments in call to 'scale'",
        "Unknown named parameter 'z' for function 'scale'",
        "List element type does not match",
    ])


def test_opaque_provider_is_not_type_checked():
    source = ROOT / "examples" / "provider_cases" / "bad_opaque.du"
    compiled = compile_program(source)
    output = compiled.stdout + compiled.stderr
    assert compiled.returncode != 0, output
    assert "Semantic validation failed" not in output, output
    assert "Argument type mismatch" not in output, output
    assert "dmd compilation failed" in output, output


def test_opaque_provider_rejects_named_arguments():
    source = ROOT / "examples" / "provider_cases" / "bad_opaque_named.du"
    assert_rejected(source, [
        "Named argument 'text' is not supported in call to 'echo'",
    ])


def test_unreadable_provider_signature_stays_opaque():
    source = ROOT / "examples" / "provider_cases" / "bad_unreadable.du"
    compiled = compile_program(source)
    output = compiled.stdout + compiled.stderr
    assert compiled.returncode == 1, output
    assert "Provider signature was not understood and is not checked: this is not a signature" in output, output
    assert "Argument type mismatch" not in output, output
    assert "Semantic validation failed" in output, output
    assert "dmd compilation failed" not in output, output


def test_methods_constructors_fields_and_defaults():
    source = ROOT / "examples" / "type_cases" / "use_methods.du"
    assert run_program(source) == ["e", "4", "1", "5", "8", "2", "2", "6", "1", "arb", "arbrc"]


def test_imported_frame_method():
    source = ROOT / "examples" / "type_cases" / "use_imported.du"
    assert run_program(source) == ["5"]


@pytest.mark.parametrize("name, diagnostics", [
    ("type_cases/bad_method_type", ["List element type does not match"]),
    ("type_cases/bad_method_name", ["Named argument 'extra' is not supported in call to method 'grow'"]),
    ("type_cases/bad_arity", [
        "Missing argument for parameter 'extra' in call to 'grow'",
        "Too many arguments in call to 'grow'",
    ]),
    ("type_cases/bad_ctor", [
        "Too many arguments in call to 'Row'",
        "Named argument 'cells' is not supported in call to constructor 'Row'",
    ]),
    ("type_cases/bad_field", ["Assigned expression type does not match field 'picked'"]),
    ("type_cases/bad_default", [
        "List element type does not match",
        "Non-default parameter 'y' cannot follow",
        "must be a compile-time constant",
    ]),
    ("type_cases/bad_imported_method", ["Ok payload type does not match"]),
    ("type_cases/bad_imported_let", ["Cannot call mutating method 'add' on let binding 'c'"]),
])
def test_method_contract_rejected(name, diagnostics):
    source = ROOT / "examples" / (name + ".du")
    assert_rejected(source, diagnostics)
