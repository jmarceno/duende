import shutil
import os
import subprocess
import tempfile

import pytest

BUILD_DIR = "examples/duende_build"

def pytest_sessionstart(session):
    # Run only in master (xdist controller) OR when xdist is not used
    if getattr(session.config, "workerinput", None) is None:
        if os.path.exists(BUILD_DIR):
            shutil.rmtree(BUILD_DIR)
        os.makedirs(BUILD_DIR, exist_ok=True)        
        print(f"\n[pytest setup] Cleaned and recreated {BUILD_DIR}/")

def pytest_sessionfinish(session, exitstatus):
    # Run only in master (xdist controller) OR when xdist is not used
    if getattr(session.config, "workerinput", None) is None:
        if os.path.exists(BUILD_DIR):
            shutil.rmtree(BUILD_DIR)
        print(f"\n[pytest teardown] Removed {BUILD_DIR}")

_dub_probe_cache = {}


def require_dub_packages(dependencies, sub_configurations=None):
    """Skip the calling test unless dub can resolve these packages offline.

    Examples that import a provider with [dub] dependencies are built by dub. The test should
    exercise the package, not the network, so it only runs when the exact versions the compiler
    asks for are already in dub's local cache (or registered with `dub add-local`).
    `dependencies` maps package name -> version spec as the compiler writes it in its temp dub.sdl
    (provider manifest, with pins from source/duende/pinned_versions.d applied).
    """
    sub_configurations = sub_configurations or {}
    key = (tuple(sorted(dependencies.items())), tuple(sorted(sub_configurations.items())))
    if key not in _dub_probe_cache:
        with tempfile.TemporaryDirectory(prefix="duende_dub_probe_") as root:
            lines = ['name "probe"', 'targetType "executable"']
            lines += [f'dependency "{name}" version="{spec}"' for name, spec in dependencies.items()]
            lines += [f'subConfiguration "{name}" "{conf}"' for name, conf in sub_configurations.items()]
            with open(os.path.join(root, "dub.sdl"), "w") as f:
                f.write("\n".join(lines) + "\n")
            os.makedirs(os.path.join(root, "source"))
            with open(os.path.join(root, "source", "app.d"), "w") as f:
                f.write("void main() {}\n")
            try:
                probe = subprocess.run(
                    ["dub", "describe", "--skip-registry=all", "--root=" + root],
                    capture_output=True, text=True, timeout=300,
                )
                ok, detail = probe.returncode == 0, probe.stderr + probe.stdout
            except FileNotFoundError:
                ok, detail = False, "dub is not installed"
        error = next((ln.strip() for ln in detail.splitlines() if ln.strip().startswith("Error")), detail.strip()[-300:])
        _dub_probe_cache[key] = (ok, error)
    ok, error = _dub_probe_cache[key]
    if not ok:
        wanted = ", ".join(f"{name}@{spec}" for name, spec in dependencies.items())
        pytest.skip(f"dub packages not available offline ({wanted}): {error}. "
                    f"Build the example once with network access so dub caches them.")


@pytest.fixture
def require_dub():
    return require_dub_packages
