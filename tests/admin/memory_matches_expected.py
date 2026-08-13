#!/usr/bin/env python3
"""The nube's memory is what we expect after applying the config.

memory sits outside qixos-rebuild's model, so apply never reconciles it. Change it
by hand and this test stays red until you change it back, which is what makes it
usable for checking that a red result actually reaches you.

usage: memory_matches_expected.py <flake-ref> <vm> <expected-mb>
"""
import subprocess
import sys


def main(argv):
    if len(argv) != 4:
        print(f"usage: {argv[0]} <flake-ref> <vm> <expected-mb>", file=sys.stderr)
        return 2
    flake, vm, expected = argv[1:]

    # Not captured: an apply runs for minutes and its progress should be visible.
    subprocess.run(["qixos-rebuild", "--flake", flake, "apply"], check=True)

    actual = subprocess.run(
        ["qvm-prefs", vm, "memory"], check=True, capture_output=True, text=True
    ).stdout.strip()

    if actual != expected:
        print(f"{vm} memory is {actual}, expected {expected}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
