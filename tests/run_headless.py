"""Run headless Godot integration tests; parse errors must fail even if Godot exits 0."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
godot = sys.argv[1] if len(sys.argv) > 1 else "godot"
failed = []
tests = sorted((root / "tests").glob("*_test.gd"))
for test in tests:
    if test.name == "editor_pointer_test.gd":
        continue
    try:
        run = subprocess.run(
            [godot, "--headless", "--path", str(root), "--log-file",
             f"/private/tmp/tractionism-{test.stem}.log", "--script", str(test)],
            capture_output=True, text=True, timeout=90,
        )
        output = run.stdout + run.stderr
        # macOS's restricted test environment cannot read system CA certificates.
        errors = [line for line in output.splitlines()
                  if ("ERROR:" in line or "SCRIPT ERROR" in line)
                  and 'Condition "ret != noErr"' not in line]
        ok = run.returncode == 0 and not errors and ("PASS:" in output or "0 failures" in output)
        print(f"{'PASS' if ok else 'FAIL'} {test.name}", flush=True)
        if not ok:
            print(output, flush=True)
            failed.append(test.name)
    except subprocess.TimeoutExpired:
        print(f"FAIL {test.name}: timed out", flush=True)
        failed.append(test.name)
print(f"\n{len(failed)} failing suites", flush=True)
sys.exit(bool(failed))
