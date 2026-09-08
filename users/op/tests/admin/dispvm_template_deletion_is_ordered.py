#!/usr/bin/env python3
"""Removing a dispvm template, with and without the nube that names it.

Qubes refuses to remove a qube another one still points at, and `defaultDispvm` is such a
pointer. Two configs make the two halves of that:

  - dropping both ends, which qubes accepts only if the nube naming it goes first. Any
    order qixos-rebuild picks has to end with both gone.
  - dropping only the qube being pointed at, which no ordering resolves. That has to be
    refused, and refused before anything is deleted, since a config error should not cost
    a qube.

Everything here is qubes-level, so the applies run `--no-switch`. Nothing is booted; the
qubes only have to exist to be deleted, which is also why the first apply is a fixture
rather than a dependency on whatever scenario ran before.

usage: dispvm_template_deletion_is_ordered.py <flake-dir> <dispvm-template> <user>
"""
import subprocess
import sys


def apply(flake, output):
    return subprocess.run(
        ["qixos-rebuild", "--flake", f"{flake}#{output}", "apply", "--no-switch"],
        capture_output=True, text=True,
    )


def exists(vm):
    return subprocess.run(
        ["qvm-check", vm], capture_output=True, text=True
    ).returncode == 0


def main(argv):
    if len(argv) != 4:
        print(f"usage: {argv[0]} <flake-dir> <dispvm-template> <user>", file=sys.stderr)
        return 2
    flake, dispvm_template, user = argv[1:4]

    # The fixture. A no-op when the fleet is already up, and builds it when it is not.
    fixture = apply(flake, "smoke")
    if fixture.returncode != 0:
        print(f"could not establish the fleet: {fixture.stderr.strip()}", file=sys.stderr)
        return 1

    missing = [vm for vm in (dispvm_template, user) if not exists(vm)]
    if missing:
        print(f"apply did not create {', '.join(missing)}, so there is nothing to remove",
              file=sys.stderr)
        return 1

    # Refused, and nothing destroyed. Ordered first, while both are still there.
    refused = apply(flake, "smokeWithoutDvm")
    if refused.returncode == 0:
        print(f"removing {dispvm_template} while {user} still names it as its "
              "defaultDispvm was accepted, and should not have been", file=sys.stderr)
        return 1

    # The claim worth making: the refusal happened before any deletion. A check that ran
    # too late would leave one of these gone and still report a non-zero exit.
    for vm in (dispvm_template, user):
        if not exists(vm):
            print(f"the apply was refused but {vm} is gone, so something was deleted "
                  f"before the refusal:\n  {refused.stderr.strip()}", file=sys.stderr)
            return 1

    # Accepted, in whatever order qixos-rebuild works out.
    removed = apply(flake, "smokeWithoutDispvmPair")
    if removed.returncode != 0:
        print(f"removing {dispvm_template} and {user} together failed: "
              f"{removed.stderr.strip()}", file=sys.stderr)
        return 1

    left = [vm for vm in (dispvm_template, user) if exists(vm)]
    if left:
        print(f"{', '.join(left)} survived a config that declares neither", file=sys.stderr)
        return 1

    print(f"{user} then {dispvm_template} removed together, and neither alone")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
