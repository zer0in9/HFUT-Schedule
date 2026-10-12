"""Run a CI command with a deadline, terminating its process group on timeout."""
import os
import signal
import subprocess
import sys


def run(seconds, command):
    print(f"Running (timeout {seconds}s): {' '.join(command)}", flush=True)
    process = subprocess.Popen(command, start_new_session=True)
    try:
        return process.wait(timeout=seconds)
    except subprocess.TimeoutExpired:
        print(f"Timed out after {seconds}s: {' '.join(command)}", file=sys.stderr, flush=True)
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        return 124


if __name__ == "__main__":
    sys.exit(run(float(sys.argv[1]), sys.argv[2:]))
