#!/usr/bin/env python3
"""Applying an already converged config leaves nothing pending.

Usage: apply_is_idempotent.py <outer-config-flake-ref>
"""
import subprocess
import sys


def pending_changes(diff_output):
    """Lines of `qixos-rebuild diff` that describe work still to do.

    `diff` reports by printing and exits 0 either way, so its output is the only
    signal. Every line is a section header or "none", and matching that shape
    rather than expected wording means a section added to `diff` later reads as a
    header plus "none" and is ignored, while an entry like "  + smoke-nube" is
    still caught.
    """
    return [
        line
        for line in diff_output.splitlines()
        if line.strip() and line.strip() != "none" and not line.rstrip().endswith(":")
    ]


def main(argv):
    if len(argv) != 2:
        print(f"usage: {argv[0]} <outer-config-flake-ref>", file=sys.stderr)
        return 2
    flake = argv[1]

    # Not captured: an apply can run for minutes and its progress should be
    # visible rather than arriving all at once after it finishes.
    try:
        subprocess.run(["qixos-rebuild", "--flake", flake, "apply"], check=True)
    except subprocess.CalledProcessError as e:
        print(f"apply failed with exit code {e.returncode}", file=sys.stderr)
        return 1

    try:
        diff = subprocess.run(
            ["qixos-rebuild", "--flake", flake, "diff"],
            check=True, capture_output=True, text=True,
        )
    except subprocess.CalledProcessError as e:
        print(f"diff failed with exit code {e.returncode}", file=sys.stderr)
        print(e.stderr, file=sys.stderr)
        return 1

    changes = pending_changes(diff.stdout)
    if changes:
        print("apply left changes pending:", file=sys.stderr)
        print(diff.stdout, file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
