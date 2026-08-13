#!/usr/bin/env python3
"""The nube's memory is what we expect after applying the config.

memory is not implemented yet: it is absent from `VmProperties`, so an outer config
declaring it is ignored and apply does not reconcile it. This test is written for
the behaviour once it is, and stays red until then.

usage: memory_matches_expected.py <flake-ref> <vm> <expected-mb>
"""
import subprocess
import sys


def cleanup(vm):
    """Remove the qube this test created.

    By name, not by reconciling to an empty outer config. Reconciling to empty is
    scoped to the management tag, not to a scenario, so it would also destroy
    every other qube this admin manages.
    """
    result = subprocess.run(
        ["qvm-remove", "-f", vm], capture_output=True, text=True
    )
    if result.returncode != 0:
        # Warn rather than fail: a cleanup problem must not be mistaken for the
        # result of the test, but it must not pass unnoticed either.
        print(f"cleanup: could not remove {vm}: {result.stderr.strip()}", file=sys.stderr)


def main(argv):
    if len(argv) != 4:
        print(f"usage: {argv[0]} <flake-ref> <vm> <expected-mb>", file=sys.stderr)
        return 2
    flake, vm, expected = argv[1:]

    try:
        # --no-switch: this asserts on qubes-level state, which `apply` reconciles
        # before the switch. Building the nube's closure could not change the
        # answer and would make a broken switch show up as a red memory test.
        subprocess.run(
            ["qixos-rebuild", "--flake", flake, "apply", "--no-switch"], check=True
        )

        actual = subprocess.run(
            ["qvm-prefs", vm, "memory"], check=True, capture_output=True, text=True
        ).stdout.strip()

        if actual != expected:
            print(f"{vm} memory is {actual}, expected {expected}", file=sys.stderr)
            return 1
        return 0
    finally:
        # In `finally` because the run that crashes is the one whose leftovers
        # matter most.
        cleanup(vm)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
