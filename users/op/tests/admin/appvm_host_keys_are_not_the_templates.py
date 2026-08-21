#!/usr/bin/env python3
"""An AppVM does not present, or hold, its template's ssh host keys.

An AppVM's root volume is a snapshot of its template's, so a host key in the template's
/etc/ssh is in the AppVM too, and sshd uses an existing key rather than generating one.
Every AppVM in the cluster then answers as the same machine.

Two qubes have to be read, so this is an admin test rather than an in-nube one.

The template must have host keys for this to mean anything, so that is checked first and
treated as a broken scenario rather than a pass.

Private key material never crosses the tunnel: each side hashes its own.

usage: appvm_host_keys_are_not_the_templates.py <template> <appvm> [<appvm>...]
"""
import sys

import harness


def check(vm, template_keys, template_hashes):
    """Assert one AppVM is free of the template's identity. True if it is."""
    ok = True

    keys = harness.public_host_keys(vm)
    if keys is None:
        print(f"{vm} has no ssh host keys", file=sys.stderr)
        return False

    shared = keys.intersection(template_keys)
    if shared:
        ok = False
        print(f"{vm} presents its template's host key(s):", file=sys.stderr)
        for key in sorted(shared):
            print(f"  {key}", file=sys.stderr)

    # An AppVM can present a key of its own while still holding the template's, under
    # any name in /etc/ssh.
    hashes = harness.etc_ssh_hashes(vm)
    if hashes is None:
        return False

    for digest, path in sorted(hashes.items()):
        if digest in template_hashes:
            ok = False
            print(
                f"{vm}:{path} is the template's {template_hashes[digest]}",
                file=sys.stderr,
            )

    # The store is world readable and shared by the whole cluster, so a private host
    # key there is a leak however it arrived. Only this nube's keys and its template's
    # count: nixpkgs carries dummy keys under the same names.
    in_store = harness.store_host_key_hashes(vm)
    if in_store is None:
        return False

    own = harness.private_host_key_hashes(vm)
    if not own:
        print(f"{vm} has no readable private host keys", file=sys.stderr)
        return False

    secrets = set(template_hashes).union(own)
    for digest, path in sorted(in_store.items()):
        if digest in secrets:
            ok = False
            print(f"{vm}: private host key in the shared store: {path}", file=sys.stderr)

    return ok


def main(argv):
    if len(argv) < 3:
        print(f"usage: {argv[0]} <template> <appvm> [<appvm>...]", file=sys.stderr)
        return 2
    template, appvms = argv[1], argv[2:]

    # A template commits its root volume on shutdown and an AppVM snapshots that
    # committed state, so keys generated during the template's current session are
    # absent from what the AppVMs boot from. A fresh boot also re-registers qrexec
    # services, which an in-place switch does not do until the template reboots.
    if not harness.boot(template):
        return 1

    template_keys = harness.public_host_keys(template)
    template_hashes = harness.private_host_key_hashes(template)

    if template_keys is None or not template_hashes:
        print(
            f"{template} has no ssh host keys, so this test cannot prove anything. "
            "The scenario is supposed to give it some.",
            file=sys.stderr,
        )
        return 1

    rc = 0
    for vm in appvms:
        # Freshly booted: one that was already running may predate the switch.
        if not harness.boot(vm):
            rc = 1
            continue

        if check(vm, template_keys, template_hashes):
            print(f"{vm} has an identity of its own, none of {template}'s")
        else:
            rc = 1

    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
