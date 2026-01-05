#!/usr/bin/env python3
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    subprocess.run(["just", "build"], cwd=ROOT, check=True)
    bin_path = subprocess.check_output(
        ["swift", "build", "--show-bin-path"],
        cwd=ROOT,
        text=True,
    ).strip()
    frame_path = tempfile.mktemp(prefix="stoa-chromium-", suffix=".png")

    env = os.environ.copy()
    env["DYLD_FRAMEWORK_PATH"] = str(ROOT / "Libraries/CEF")
    env["DYLD_LIBRARY_PATH"] = str(
        ROOT / "Libraries/CEF/Chromium Embedded Framework.framework/Libraries"
    )
    env["STOA_CHROMIUM_AUTOSTART_URL"] = "data:text/html,<html><body>CEF OK</body></html>"
    env["STOA_CHROMIUM_DUMP_FRAME_PATH"] = frame_path
    env["STOA_CEF_LOG_PATH"] = str(ROOT / "cef.log")
    env["STOA_CEF_ALLOW_KEYCHAIN"] = "0"
    env["STOA_CHROMIUM_DEBUG"] = "1"

    proc = subprocess.Popen(
        [str(Path(bin_path) / "stoa")],
        cwd=ROOT,
        env=env,
    )
    try:
        for _ in range(120):
            if os.path.exists(frame_path) and os.path.getsize(frame_path) > 0:
                print(f"Chromium render OK: {frame_path}")
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                return 0
            time.sleep(0.1)
        print("Chromium render failed: no frame dump produced")
        return 1
    finally:
        if proc.poll() is None:
            proc.kill()


if __name__ == "__main__":
    sys.exit(main())
