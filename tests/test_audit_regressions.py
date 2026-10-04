"""Compile complete Duende programs and check runtime behavior or diagnostics."""
from pathlib import Path
import subprocess

import pytest

ROOT = Path(__file__).parent.parent
COMPILER = ROOT / "duende"


def compile_program(source):
    return subprocess.run([str(COMPILER), str(source)], cwd=ROOT,
                          capture_output=True, text=True, timeout=30)


@pytest.mark.parametrize("name, expected", [
    ("audit_regressions", ["b", "1", "1", "ti", "1", "1", "1", "tidn", "-1", "2",
                           "abc", "xbc", "xbc", "xBC", "xbc", "10", "café 😀",
                           "3", "0.5", "4", "-1", "5", "-1", "0", "8", "hello", "-1", "12"]),
    ("audit_match", ["7"]),
    ("audit_imports", ["42", "42", "42"]),
    ("audit_defer", ["body", "deferred"]),
])
def test_audit_program(name, expected):
    source = ROOT / "examples" / (name + ".du")
    compiled = compile_program(source)
    assert compiled.returncode == 0, compiled.stdout + compiled.stderr
    binary = source.parent / "duende_build" / name
    ran = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
    assert ran.returncode == 0, ran.stderr
    assert ran.stdout.splitlines() == expected


@pytest.mark.parametrize("name, diagnostic", [
    ('elif_let', "Cannot mutate let binding 'b'"),
    ('defer_let', "Cannot call mutating method 'bump' on let binding 'b'"),
    ('builtin_let', "Cannot mutate let binding 'b'"),
    ('hidden_let', "Cannot call mutating method 'hidden' on let binding 'b'"),
    ('elif_break', "Invalid use of 'break' outside of a loop"),
    ('method_continue', "Invalid use of 'continue' outside of a loop"),
    ('closure_break', "Invalid use of 'break' outside of a loop"),
    ('closure_scope', "Use of undefined variable 'inside'"),
    ('ok_payload', 'Ok payload type does not match'),
    ('some_payload', 'Some payload type does not match'),
    ('error_message', 'Error message must be a string'),
    ('unwrap_plain', '? else requires a Result or Maybe subject'),
    ('guard_import', "Math functions require 'import std.math'"),
    ('elif_import', "Hash and digest functions require 'import std.hash'"),
    ('assignment_import', "Math functions require 'import std.math'"),
    ('defer_import', "Math functions require 'import std.math'"),
    ('multiline_position', ':4:21: Integer literal'),
])
def test_audit_rejected_program(name, diagnostic):
    source = ROOT / "examples" / "audit_errors" / (name + ".du")
    compiled = compile_program(source)
    output = compiled.stdout + compiled.stderr
    assert compiled.returncode == 1, output
    assert diagnostic in output, output
    assert "Semantic validation failed" in output, output
    assert "dmd compilation failed" not in output, output
    assert not (source.parent / "duende_build" / name).exists()
