import shutil
import os

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