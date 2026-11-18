#!/usr/bin/env python3
"""A nube resolves through the qubes nameservers, and still does after an activation.

Qubes' `setup-ip` writes the nameservers from qubesdb into /etc/resolv.conf at boot,
deleting whatever symlink it finds there first, and hands the same servers to
systemd-resolved for eth0 with `resolvectl dns`. Both are asserted. resolved does not read
/etc/resolv.conf: without its own copy it has only its built-in public servers, and lookups
wait seconds on them and go past the netvm's DNS.

If nixos also declares /etc/resolv.conf, every activation restores the symlink to
resolved's own stub. Boot hides that: `setup-ip` runs after activation there and wins, and
its unit is a oneshot that has long exited by the time anything activates again. What this
runs is a second activation, which is what `qixos-appvm-switch` does on every boot and what
`nixos-rebuild switch` does by hand.

What is asserted is which servers the qube uses, not merely that lookups succeed: a qube
without them can keep resolving through the fallbacks. The state before the activation is
asserted as carefully as the state after it, so a qube that had already lost them cannot
pass this without proving anything.

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
printf 'secondary=%s\n' "$(qubesdb-read /qubes-secondary-dns 2>/dev/null)"
printf 'resolved=%s\n' "$(resolvectl dns eth0 2>&1 | cut -d: -f2-)"
"""

# The AppVM switch to the nube's own configuration, finished whether or not it worked.
SWITCHED = ("systemctl show -p ActiveState --value qixos-appvm-switch.service "
            "| grep -qx -e active -e failed")


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
            f"nameservers [{seen['servers'].strip()}], resolved uses "
            f"[{seen['resolved'].strip()}], resolves {seen['resolves']}")


def main(argv):
    if len(argv) != 2:
        print(f"usage: {argv[0]} <vm>", file=sys.stderr)
        return 2
    vm = argv[1]

    if not harness.boot(vm):
        return 1
    # setup-ip runs before the switch finishes, and the activation below must not race
    # the boot-time one. A failed switch leaves the template's configuration running.
    if not harness.wait_for(vm, SWITCHED, "the switch to its own configuration"):
        return 1
    if harness.ssh(vm, "systemctl is-failed --quiet qixos-appvm-switch").returncode == 0:
        print(f"{vm}'s switch to its own configuration failed", file=sys.stderr)
        return 1

    before = state(vm)
    if before is None:
        return 1

    expected = before.get("expected", "").strip()
    if not expected:
        print(f"{vm} has no /qubes-primary-dns in qubesdb, so there is nothing to "
              "compare against", file=sys.stderr)
        return 1
    # Both qubes nameservers, matched whole, so 10.139.1.10 does not pass for 10.139.1.1.
    wanted = {expected, before.get("secondary", "").strip()} - {""}

    def lost(seen):
        """Which of the two places is missing the qubes nameservers."""
        return [where for where, key in (("/etc/resolv.conf", "servers"),
                                         ("systemd-resolved", "resolved"))
                if not wanted <= set(seen[key].split())]

    # The precondition. Without it a qube that had already lost them passes silently.
    if lost(before):
        print(f"{vm} was not using the qubes nameservers in {' and '.join(lost(before))} "
              "before anything was activated:", file=sys.stderr)
        print(describe("before", before), file=sys.stderr)
        print(f"  expected both to list {' '.join(sorted(wanted))}", file=sys.stderr)
        return 1

    activated = harness.ssh(vm, "sudo /run/current-system/bin/switch-to-configuration test")
    if activated.returncode != 0:
        print(f"could not activate {vm}'s configuration: {activated.stderr.strip()}",
              file=sys.stderr)
        return 1

    after = state(vm)
    if after is None:
        return 1

    if not lost(after):
        print(f"{vm} still uses the qubes nameservers after activating its configuration, "
              "in /etc/resolv.conf and in systemd-resolved")
        return 0

    print(f"{vm} lost the qubes nameservers in {' and '.join(lost(after))} when its "
          "configuration was activated:", file=sys.stderr)
    print(describe("before", before), file=sys.stderr)
    print(describe("after ", after), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
