#!/usr/bin/env python3
"""Two AppVMs of one cluster do not share an ssh host key.

Siblings share a template and therefore a root volume snapshot, so putting one key in
the template gives every AppVM in the cluster the same identity. This catches that
without needing the template, along with anything else that derives one identity per
cluster.

usage: sibling_appvms_have_distinct_host_keys.py <appvm> <appvm> [<appvm>...]
"""
import itertools
import sys

import harness


def main(argv):
    if len(argv) < 3:
        print(f"usage: {argv[0]} <appvm> <appvm> [<appvm>...]", file=sys.stderr)
        return 2
    appvms = argv[1:]

    keys = {}
    for vm in appvms:
        if not harness.boot(vm):
            return 1

        found = harness.public_host_keys(vm)
        if found is None:
            print(f"{vm} has no ssh host keys", file=sys.stderr)
            return 1
        keys[vm] = found

    rc = 0
    for a, b in itertools.combinations(appvms, 2):
        shared = keys[a].intersection(keys[b])
        if shared:
            rc = 1
            print(f"{a} and {b} share host key(s):", file=sys.stderr)
            for key in sorted(shared):
                print(f"  {key}", file=sys.stderr)

    if rc == 0:
        print(f"{len(appvms)} siblings, no host key in common")
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
