#!/usr/bin/env python3
"""A cluster too heavy to evaluate in one go still switches.

A template used to evaluate itself and every AppVM of its cluster in a single nix, so the
memory a switch needed was the sum of them all. qixos.Switch now builds the template and
then each AppVM with a nix of its own, and needs only as much as the largest. The fixture
is sized between the two: each AppVM fits in the template's memory and the four of them
together do not. See the `sequenced` config in outer-configs/oom.

Passing takes more than the apply succeeding. A qixos.Switch from before AppVMs were
built separately, which is what a template cloned from an older base template carries,
builds the template alone when handed this version's library and exits 0 having built no
AppVM. So each AppVM's closure is looked for on the template as well, where an AppVM
would find it at boot.

usage: heavy_cluster_switches_one_appvm_at_a_time.py <flake-ref> <template> <appvm>...
"""
import subprocess
import sys

import harness

# From qixos core. Where qixos.Switch leaves each AppVM's built configuration.
ACTIVATION_DIR = "/var/qixos/activation"


def main(argv):
    if len(argv) < 4:
        print(f"usage: {argv[0]} <flake-ref> <template> <appvm>...", file=sys.stderr)
        return 2

    flake, template, appvms = argv[1], argv[2], argv[3:]

    # The template outlives each run, and so do the AppVMs' closures from earlier ones,
    # which a switch that built nothing would leave in place. Cleared, so any closure
    # found afterwards was built by this switch. Left running for the apply, whose switch
    # runs on this same template and whose closing shutdown commits the clearing. A
    # template that does not exist has nothing to clear: the oom scenario's other config
    # shares this management tag, so applying it removes this cluster.
    if subprocess.run(["qvm-check", template], capture_output=True).returncode == 0:
        if not harness.boot(template):
            return 1
        cleared = harness.ssh(template, "sudo", "rm", "-rf", ACTIVATION_DIR)
        if cleared.returncode != 0:
            print(f"could not clear {ACTIVATION_DIR} on {template}: {cleared.stderr.strip()}", file=sys.stderr)
            return 1

    # --update for the reason `run` gives: without it the template builds the copy of
    # this local flake it locked on a previous run.
    result = subprocess.run(
        ["qixos-rebuild", "--flake", flake, "apply", "--update"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(
            f"the switch of {template} failed. If it was killed for memory then its "
            f"AppVMs were evaluated together, since each one alone fits:",
            file=sys.stderr,
        )
        print((result.stdout + result.stderr).strip(), file=sys.stderr)
        return 1

    # The template was shut down by the apply, which is what commits its root volume.
    if not harness.boot(template):
        return 1

    unbuilt = [
        appvm for appvm in appvms
        if harness.ssh(
            template, "test", "-x", f"{ACTIVATION_DIR}/{appvm}/nixos/bin/switch-to-configuration"
        ).returncode != 0
    ]
    harness.shut_down(template)

    if unbuilt:
        print(
            f"the switch of {template} succeeded but built nothing for {', '.join(unbuilt)}. "
            f"A template whose qixos.Switch predates separate AppVM builds does this on "
            f"its first switch, and the next one builds them.",
            file=sys.stderr,
        )
        return 1

    print(f"{template} built {len(appvms)} AppVMs that do not fit in its memory together")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
