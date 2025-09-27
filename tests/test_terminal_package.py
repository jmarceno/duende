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
    return run.stdout.strip()


def test_terminal_package_simple():
    src = ROOT / "examples" / "terminal_demo.du"
    out = compile_and_run(src).strip()
    assert out == "Terminal module available"
