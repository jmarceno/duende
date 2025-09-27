from pathlib import Path
import subprocess
import pytest

ROOT = Path(__file__).parent.parent
DUENDE = ROOT / "duende"


def compile_and_run(source_file: Path):
    result = subprocess.run([str(DUENDE), str(source_file)], cwd=ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"compile failed: {result.stderr}\n{result.stdout}")
    build_dir = source_file.parent / "duende_build"
    exe = build_dir / source_file.stem
    run = subprocess.run([str(exe)], cwd=ROOT, capture_output=True, text=True)
    return run.stdout.strip()


def test_wildcard_imports():
    src = ROOT / "examples" / "imports_cases" / "wildcard" / "use_wildcard.du"
    out = compile_and_run(src).splitlines()
    assert out == ["1", "2"]


def test_multiple_aliases_one_import():
    src = ROOT / "examples" / "imports_cases" / "multi_alias" / "use_aliases.du"
    out = compile_and_run(src).splitlines()
    assert out == ["1", "2", "3"]


def test_reexport_public_import():
    src = ROOT / "examples" / "imports_cases" / "reexport" / "use_reexport.du"
    out = compile_and_run(src).splitlines()
    assert out == ["3"]


def test_circular_imports_runtime():
    src = ROOT / "examples" / "imports_cases" / "circular" / "use_circular.du"
    out = compile_and_run(src).splitlines()
    assert out == ["1", "2"]


def test_packages_simple_provider(tmp_path):
    src = ROOT / "examples" / "packages_simple.du"
    out = compile_and_run(src).strip()
    assert out == "hello"


def test_packages_std_csv_provider():
    src = ROOT / "examples" / "std_csv_example.du"
    out = compile_and_run(src).splitlines()
    # Expect the first data record (Alice,30)
    assert out == ["Alice", "30"]


def test_packages_std_json_provider():
    src = ROOT / "examples" / "std_json_example.du"
    out = compile_and_run(src).splitlines()
    # Expect the fields from the JSON object
    assert out == ["D", "4", "a", "D", "3.5"]
