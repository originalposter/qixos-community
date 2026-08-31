#!/usr/bin/env python3
"""A nube's user units have no task limit sized by the RAM it booted with.

A qixos nube boots at its `memory` allocation and qmemman balloons it up afterwards. The
kernel computes `threads-max` from the memory present at init and never recomputes it, and
systemd takes `DefaultTasksMax` as 15% of that, also once. So a nube that ends up with
gigabytes keeps a thread ceiling sized for its boot allocation.

Apps launched through the qrexec fork server run as user units, so they inherit that
ceiling. Firefox exceeds it across its content processes, `clone()` returns EAGAIN, and
thread creation fails somewhere that does not expect to fail.

Only `infinity` passes. A number would mean someone picked a ceiling on purpose, which is
a decision worth making deliberately here rather than having this test wave it through.

usage: task_limit_is_not_sized_by_boot_memory.py <vm>
"""
import sys

import harness


def main(argv):
    if len(argv) != 2:
        print(f"usage: {argv[0]} <vm>", file=sys.stderr)
        return 2
    vm = argv[1]

    if not harness.boot(vm):
        return 1

    limit = harness.ssh(vm, "systemctl --user show -p DefaultTasksMax --value")
    if limit.returncode != 0:
        print(f"could not read the task limit on {vm}: {limit.stderr.strip()}", file=sys.stderr)
        return 1

    actual = limit.stdout.strip()
    if not actual:
        print(f"{vm} reported no DefaultTasksMax, so there is no user manager to ask",
              file=sys.stderr)
        return 1

    if actual == "infinity":
        print(f"{vm} user units have no task limit")
        return 0

    # Where the number came from, since on its own it looks arbitrary rather than derived.
    threads_max = harness.ssh(vm, "cat /proc/sys/kernel/threads-max").stdout.strip()
    mem = harness.ssh(vm, "grep MemTotal /proc/meminfo").stdout.strip()
    print(
        f"{vm} caps user units at {actual} tasks, which is 15% of a threads-max of "
        f"{threads_max}, itself fixed at boot from the memory the nube started with.\n"
        f"  it has since ballooned to: {mem}",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
