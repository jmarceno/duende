from pathlib import Path
import subprocess

ROOT = Path(__file__).parent.parent
DUENDE = ROOT / "duende"

def compile_and_run(source_file: Path):
    result = subprocess.run([str(DUENDE), str(source_file)], cwd=ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"compile failed: {result.stderr}\n{result.stdout}")
    build_dir = source_file.parent / "duende_build"
    exe = build_dir / source_file.stem
    run = subprocess.run([str(exe)], cwd=ROOT, capture_output=True, text=True)
    assert run.returncode == 0, f"program failed: {run.stderr}"
    return run.stdout


def test_terminal_package_simple(require_dub):
    require_dub({"arsd-official:terminal": "==12.0.0"})
    src = ROOT / "examples" / "terminal_demo.du"
    assert compile_and_run(src) == "Terminal module available\n"
