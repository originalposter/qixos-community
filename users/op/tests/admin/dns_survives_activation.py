#!/usr/bin/env python3
"""A nube resolves through the qubes nameservers, and still does after an activation.

Two things own /etc/resolv.conf. Qubes' `setup-ip` writes the nameservers from qubesdb
into it at boot, deleting whatever symlink it finds there first, and systemd-resolved
reads them back out of it as its upstream servers. If nixos also declares the file, every
activation restores the symlink to resolved's own stub, and resolved is left with no
upstream at all: the qube keeps its addresses and its routes and resolves nothing.

Boot hides it. `setup-ip` runs after activation there and wins, and its unit is a oneshot
that has long exited by the time anything activates again, so nothing re-applies it. What
this runs is a second activation, which is what `qixos-appvm-switch` does on every boot
and what `nixos-rebuild switch` does by hand.

What is asserted is which servers the qube uses, not merely that lookups succeed. A qube
that has lost them does not necessarily fail: systemd-resolved falls back to its own
public servers, 1.1.1.1 and 8.8.8.8 among them, and the netvm redirects DNS anyway, so
lookups can keep working while every query goes somewhere it was never meant to. That is
also why the breakage looks intermittent, since whether a qube appears broken depends on
whether the fallback happens to work.

The state before the activation is asserted as carefully as the state after it, so a qube
that had already lost them cannot pass this without proving anything.

usage: dns_survives_activation.py <vm>
"""
import sys

import harness

# A name to look up. Secondary to which servers are configured, but a nube that cannot
# resolve at all has a different problem worth naming separately.
PROBE_NAME = "cache.nixos.org"

STATE = r"""
printf 'type=%s\n' "$(stat -c %F /etc/resolv.conf 2>/dev/null || echo missing)"
printf 'servers=%s\n' "$(awk '/^nameserver/ {printf "%s ", $2}' /etc/resolv.conf 2>/dev/null)"
printf 'resolves=%s\n' "$(getent hosts """ + PROBE_NAME + r""" >/dev/null 2>&1 && echo yes || echo no)"
printf 'expected=%s\n' "$(qubesdb-read /qubes-primary-dns 2>/dev/null)"
"""


def state(vm):
    """How the qube's resolver looks right now, or None if it could not be asked."""
    result = harness.ssh(vm, STATE)
    if result.returncode != 0:
        print(f"could not read resolver state on {vm}: {result.stderr.strip()}",
              file=sys.stderr)
        return None
    return dict(
        line.split("=", 1) for line in result.stdout.splitlines() if "=" in line
    )


def describe(where, seen):
    return (f"  {where}: /etc/resolv.conf is a {seen['type']}, "
            f"nameservers [{seen['servers'].strip()}], resolves {seen['resolves']}")


def main(argv):
    if len(argv) != 2:
        print(f"usage: {argv[0]} <vm>", file=sys.stderr)
        return 2
    vm = argv[1]

    if not harness.boot(vm):
        return 1

    before = state(vm)
    if before is None:
        return 1

    expected = before.get("expected", "").strip()
    if not expected:
        print(f"{vm} has no /qubes-primary-dns in qubesdb, so there is nothing to "
              "compare against", file=sys.stderr)
        return 1

    # The precondition. Without it a qube that had already lost them passes silently.
    if expected not in before["servers"]:
        print(f"{vm} was not using the qubes nameservers before anything was activated, "
              "so this says nothing about activation:", file=sys.stderr)
        print(describe("before", before), file=sys.stderr)
        print(f"  expected to find {expected} among them", file=sys.stderr)
        return 1

    activated = harness.ssh(vm, "sudo /run/current-system/bin/switch-to-configuration test")
    if activated.returncode != 0:
        print(f"could not activate {vm}'s configuration: {activated.stderr.strip()}",
              file=sys.stderr)
        return 1

    after = state(vm)
    if after is None:
        return 1

    if expected in after["servers"]:
        print(f"{vm} still uses the qubes nameservers after activating its configuration")
        return 0

    print(f"{vm} lost the qubes nameservers when its configuration was activated. "
          f"Lookups may still appear to work through resolved's public fallbacks.",
          file=sys.stderr)
    print(describe("before", before), file=sys.stderr)
    print(describe("after ", after), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
