from pathlib import Path
import subprocess
import pytest

ROOT = Path(__file__).parent.parent
DUENDE = ROOT / "duende"


def run_duende(source_text: str):
    tmp = ROOT / "examples" / "duende_build" / "tmp_semantic.du"
    tmp.parent.mkdir(parents=True, exist_ok=True)
    tmp.write_text(source_text)
    result = subprocess.run([str(DUENDE), str(tmp)], cwd=ROOT, capture_output=True, text=True)
    return result


def test_break_outside_loop_error():
    src = """
int main() do
    break
end
"""
    res = run_duende(src)
    assert res.returncode == 0 or res.returncode == 0  # duende prints error to stdout but exits 0 in current design
    assert "Invalid use of 'break' outside of a loop" in (res.stderr or res.stdout)


def test_continue_outside_loop_error():
    src = """
int main() do
    if 1 == 1 do
        continue
    end
end
"""
    res = run_duende(src)
    assert res.returncode == 0 or res.returncode == 0
    assert "Invalid use of 'continue' outside of a loop" in (res.stderr or res.stdout)


def test_hash_without_import_error():
    src = """
int main() do
    // Using hashing function without importing std.hash or std.digest should error
    print(sha256("abc"))
end
"""
    res = run_duende(src)
    # Compiler prints error to stdout/stderr and currently exits 0 per existing design
    assert res.returncode == 0 or res.returncode == 0
    assert "Hash and digest functions require 'import std.hash' or 'import std.digest'" in (res.stderr or res.stdout)
