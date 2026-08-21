#!/usr/bin/env python3
"""An AppVM keeps its ssh host keys across a reboot.

An AppVM's root volume is a fresh snapshot of its template's on every boot, so anything
at /etc/ssh that was not written somewhere persistent is gone. A test inside the nube
cannot survive that, so this runs from the runner.

Read alongside appvm_host_keys_are_not_the_templates.py: a host key baked into the
template would satisfy this test too, and is a worse bug. The pair is what pins the
intended behaviour of one identity per AppVM.

usage: ssh_host_keys_survive_reboot.py <vm>
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

    before = harness.public_host_keys(vm)
    if before is None:
        print(f"{vm} has no ssh host keys to keep", file=sys.stderr)
        return 1

    # The public halves would still match if the private ones had been truncated
    # underneath, so check those too.
    private = harness.private_host_key_hashes(vm)
    if not private:
        print(f"{vm} has public host keys but no readable private ones", file=sys.stderr)
        return 1

    if not harness.boot(vm):
        return 1

    after = harness.public_host_keys(vm)
    if after is None:
        print(f"{vm} had host keys before the reboot and none after", file=sys.stderr)
        return 1

    if before != after:
        # Both directions, so the failure says which key types were replaced.
        print(f"{vm} did not keep its host keys across a reboot", file=sys.stderr)
        for key in sorted(before - after):
            print(f"  lost:   {key}", file=sys.stderr)
        for key in sorted(after - before):
            print(f"  gained: {key}", file=sys.stderr)
        return 1

    print(f"{vm} kept {len(before)} host key(s) across a reboot")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
