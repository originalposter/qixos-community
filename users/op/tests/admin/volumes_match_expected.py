#!/usr/bin/env python3
"""A nube's volumes are at least the size the outer config declared, filesystems too.

Two halves, because they break for unrelated reasons and only one of them is visible
from dom0. Growing the volume is qixos-rebuild reconciling and the admin API permitting
it. Growing the filesystem on that volume to match is the nube's own doing, at boot for a
nube that was down and over the `qubes.ResizeDisk` endpoint for one that was up. A volume
that grew while its filesystem stayed put looks entirely correct to `qvm-volume`.

The nube is removed before the apply as well as after. A declared size is a floor, so one
left at its declared size by an earlier run satisfies this test without this apply having
done anything, and every run after the first would pass on the previous run's work.

usage: volumes_match_expected.py <flake-ref> <vm> <volume>=<bytes> [<volume>=<bytes>...]
"""
import subprocess
import sys

import harness

# Where each volume is mounted inside a nube, fixed by qixos core's `fileSystems`.
MOUNTS = {"root": "/", "private": "/rw"}

# How much of its volume a filesystem is expected to cover. ext4 metadata takes a few
# percent and the exact share moves with the filesystem's size, so this is deliberately
# slack: the failure being watched for is a filesystem that did not grow at all, which
# sits a whole declared increment below its volume rather than a few percent.
FILLED = 0.9


def remove(vm):
    """Remove the qube, by name.

    Not by reconciling to an empty outer config, which is scoped to the management tag
    rather than to a scenario and would take every other qube this admin manages with it.
    """
    result = subprocess.run(["qvm-remove", "-f", vm], capture_output=True, text=True)
    if result.returncode != 0 and "no such domain" not in result.stderr.lower():
        # Warn rather than fail: a cleanup problem must not be mistaken for the result
        # of the test, but it must not pass unnoticed either.
        print(f"could not remove {vm}: {result.stderr.strip()}", file=sys.stderr)


def _bytes(output, what):
    """The one number a size read printed, or None with a reason if it did not."""
    try:
        return int(output.strip())
    except ValueError:
        print(f"{what} did not report a number: {output.strip()!r}", file=sys.stderr)
        return None


def volume_size(vm, volume):
    """Size of a volume in bytes as dom0 reports it, or None if it could not be read."""
    result = subprocess.run(
        ["qvm-volume", "info", f"{vm}:{volume}", "size"], capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"could not read {vm}:{volume}: {result.stderr.strip()}", file=sys.stderr)
        return None
    return _bytes(result.stdout, f"{vm}:{volume}")


def filesystem_size(vm, mount):
    """Size of the filesystem mounted at `mount` inside the nube, in bytes."""
    result = harness.ssh(vm, f"df -B1 --output=size {mount} | tail -1")
    if result.returncode != 0:
        print(f"could not read {mount} on {vm}: {result.stderr.strip()}", file=sys.stderr)
        return None
    return _bytes(result.stdout, f"{mount} on {vm}")


def main(argv):
    if len(argv) < 4 or not all("=" in arg for arg in argv[3:]):
        print(f"usage: {argv[0]} <flake-ref> <vm> <volume>=<bytes> [<volume>=<bytes>...]",
              file=sys.stderr)
        return 2
    flake, vm = argv[1:3]
    try:
        expected = {name: int(size) for name, size in
                    (arg.split("=", 1) for arg in argv[3:])}
    except ValueError:
        print("sizes are in bytes, so that this does not carry a second copy of the "
              "parser the config is read with", file=sys.stderr)
        return 2

    unknown = sorted(set(expected) - set(MOUNTS))
    if unknown:
        print(f"no mount point known for: {', '.join(unknown)}", file=sys.stderr)
        return 2

    # Before the apply, so the apply has to do the growing. See the module docstring.
    remove(vm)

    try:
        # A full apply, unlike the properties check: this one boots the nube and needs
        # a config built for it to answer ssh. --update for the reason `run` gives.
        if subprocess.run(
            ["qixos-rebuild", "--flake", flake, "apply", "--update"]
        ).returncode != 0:
            print("apply failed", file=sys.stderr)
            return 1

        # Every volume, not the first to fail: one apply is expensive enough that a run
        # should say everything it learned.
        wrong = {}
        sizes = {}
        for volume, want in expected.items():
            sizes[volume] = volume_size(vm, volume)
            if sizes[volume] is None:
                wrong[volume] = "could not read its size"
            elif sizes[volume] < want:
                wrong[volume] = f"{sizes[volume]} bytes, expected at least {want}"

        if wrong:
            print(f"{vm} has volumes below what the config declared:", file=sys.stderr)
            for volume, why in sorted(wrong.items()):
                print(f"  {volume} is {why}", file=sys.stderr)
            return 1

        # Only once dom0 agrees. A filesystem cannot be expected to fill a volume that
        # was never grown, and reporting both would name two failures for one cause.
        if not harness.boot(vm):
            return 1

        for volume, size in sizes.items():
            mount = MOUNTS[volume]
            filesystem = filesystem_size(vm, mount)
            if filesystem is None:
                wrong[volume] = f"could not read {mount}"
            elif filesystem < size * FILLED:
                wrong[volume] = (
                    f"{mount} is {filesystem} bytes on a volume of {size}, so the "
                    f"filesystem did not grow with it"
                )

        if wrong:
            print(f"{vm} has filesystems that did not follow their volumes:", file=sys.stderr)
            for volume, why in sorted(wrong.items()):
                print(f"  {volume}: {why}", file=sys.stderr)
            return 1

        print(f"{vm} matches the config on {len(expected)} volume"
              f"{'' if len(expected) == 1 else 's'}, filesystems included")
        return 0
    finally:
        # In `finally` because the run that crashes is the one whose leftovers matter
        # most.
        remove(vm)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
