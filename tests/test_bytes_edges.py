import subprocess
from pathlib import Path
import tempfile


ROOT = Path(__file__).parent.parent
DUENDE = ROOT / "duende"


def compile_and_run_source(source_text: str, name: str = "tmp_bytes_edge"):
    with tempfile.TemporaryDirectory() as td:
        tdir = Path(td)
        src = tdir / f"{name}.du"
        src.write_text(source_text)

        # Compile
        res = subprocess.run([str(DUENDE), str(src)], cwd=ROOT, capture_output=True, text=True)
        if res.returncode != 0:
            raise RuntimeError(f"Compilation failed: {res.stderr}\n{res.stdout}")

        exe = tdir / "duende_build" / name
        run = subprocess.run([str(exe)], cwd=tdir, capture_output=True, text=True)
        return run


def test_slice_out_of_bounds_runtime_error():
    src = """
let bytes b = b"hi"
print(fromBytes(b[10:12]))
"""
    run = compile_and_run_source(src, name="oob_slice")
    # Expect non-zero due to runtime range error
    assert run.returncode != 0