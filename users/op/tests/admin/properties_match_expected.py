#!/usr/bin/env python3
"""A nube's qubes-level properties are what the outer config declared.

Every expected value here must differ from the qubes default for that property. A value
that matches the default proves nothing: apply would set nothing, and qvm-prefs would
still report what was asked for.

usage: properties_match_expected.py <flake-ref> <vm> <prop>=<value> [<prop>=<value>...]
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
    if len(argv) < 4 or not all("=" in arg for arg in argv[3:]):
        print(f"usage: {argv[0]} <flake-ref> <vm> <prop>=<value> [<prop>=<value>...]",
              file=sys.stderr)
        return 2
    flake, vm = argv[1:3]
    expected = dict(arg.split("=", 1) for arg in argv[3:])

    try:
        # --no-switch: this asserts on qubes-level state, which `apply` reconciles
        # before the switch. Building the nube's closure could not change the
        # answer and would make a broken switch show up as a red property test.
        subprocess.run(
            ["qixos-rebuild", "--flake", flake, "apply", "--no-switch"], check=True
        )

        # Every property, not the first to fail: one apply is expensive enough that a
        # run should say everything it learned.
        wrong = {}
        for prop, want in expected.items():
            got = subprocess.run(
                ["qvm-prefs", vm, prop], capture_output=True, text=True
            )
            if got.returncode != 0:
                wrong[prop] = f"could not read it: {got.stderr.strip()}"
            elif got.stdout.strip() != want:
                wrong[prop] = f"{got.stdout.strip()}, expected {want}"

        if wrong:
            print(f"{vm} does not match the config:", file=sys.stderr)
            for prop, why in sorted(wrong.items()):
                print(f"  {prop} is {why}", file=sys.stderr)
            return 1

        print(f"{vm} matches the config on {len(expected)} propert"
              f"{'y' if len(expected) == 1 else 'ies'}")
        return 0
    finally:
        # In `finally` because the run that crashes is the one whose leftovers
        # matter most.
        cleanup(vm)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
