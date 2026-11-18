#!/usr/bin/env python3
"""A qube whose netvm is a nube reaches the network through it.

The nube is made a netvm by providesNetwork in the outer config and by nothing in its
inner config. dom0 then tells it it is a ProxyVM, and qixos core starts the netvm side
from that: the backend for the downstream's interface, the base and anti-spoofing
nftables rules, the firewall daemon, and forwarding.

The firewall daemon is checked after the downstream got out, not just before. It drops a
downstream's traffic until it has installed that qube's rules from dom0, so getting out
means it applied them, here dom0's default of accepting everything. But when it exits it
deletes its own rules on the way out, and the base rules underneath forward everything,
so a daemon that applied the rules and then died also lets the downstream out.

The netvm's forwarding gate must have opened only after the netvm switched to its own
configuration. Then the daemon is stopped and ip_forward forced back on, and the
downstream must lose the network: the gate, not ip_forward, is what holds forwarding to
the daemon running. This mutates the netvm, so it comes last, and it is restarted after. Whether a rule that drops is honoured is the daemon's own
logic, upstream's, not this test's.

usage: netvm_nube_serves_downstream.py <netvm> <downstream>
"""
import subprocess
import sys

import harness

# A lookup and a fetch, both forwarded by the netvm. The lookup cannot tell the netvm's
# DNS redirect from plain forwarding, since both end at the same upstream resolver, so
# the redirect is not what this checks.
PROBE_NAME = "cache.nixos.org"
FETCH = f"curl -fsS -o /dev/null --max-time 10 https://{PROBE_NAME}/nix-cache-info"
PROBE = f"getent hosts {PROBE_NAME} >/dev/null && {FETCH}"

# The AppVM switch to the nube's own configuration, finished whether or not it worked,
# the same condition the runner waits on before in-nube tests.
SWITCHED = ("systemctl show -p ActiveState --value qixos-appvm-switch.service "
            "| grep -qx -e active -e failed")

# The forwarding gate opened after the AppVM switch finished, both this boot.
GATE_AFTER_SWITCH = r"""
gate=$(systemctl show -P ActiveEnterTimestampMonotonic qixos-forwarding-gate.service)
switch=$(systemctl show -P ActiveEnterTimestampMonotonic qixos-appvm-switch.service)
echo "gate opened at ${gate:-0} us, switch finished at ${switch:-0} us"
[ "${gate:-0}" != 0 ] && [ "${switch:-0}" != 0 ] && [ "$gate" -ge "$switch" ]
"""

# What curl exits with when the network is not there: no name resolution, no connection,
# or a timeout. Anything else, an ssh failure (255) above all, says nothing about the
# network and must not count as the downstream being cut off.
CUT_OFF = {6, 7, 28}

# Long enough for the downstream's interface to come up after its ssh does.
NETWORK_DEADLINE = 120

# What the netvm side runs, for the report when the downstream cannot get out.
UNITS = ["xendriverdomain", "qubes-antispoof", "qubes-iptables", "qubes-firewall",
         "qubes-network", "qixos-forwarding-gate"]


def main(argv):
    if len(argv) != 3:
        print(f"usage: {argv[0]} <netvm> <downstream>", file=sys.stderr)
        return 2
    netvm, downstream = argv[1:]

    # The precondition. A downstream on any other netvm would pass without the nube
    # doing anything.
    named = subprocess.run(["qvm-prefs", downstream, "netvm"], capture_output=True, text=True)
    if named.stdout.strip() != netvm:
        print(f"{downstream}'s netvm is {named.stdout.strip() or named.stderr.strip()!r}, "
              f"not {netvm}, so this says nothing about {netvm}", file=sys.stderr)
        return 1

    # The downstream first, since qubes will not stop a netvm a running qube is using.
    if not (harness.shut_down(downstream) and harness.boot(netvm)
            and harness.boot(downstream)):
        return 1
    # A switch restarts any unit that differs between the template's closure and the
    # nube's own, so the checks below wait until neither nube is mid-switch.
    # A switch that failed leaves the nube on its template's configuration, which also
    # carries the netvm side, so the checks below would pass for the wrong nube.
    for vm in (netvm, downstream):
        if not harness.wait_for(vm, SWITCHED, "the switch to its own configuration"):
            return 1
        if harness.ssh(vm, "systemctl is-failed --quiet qixos-appvm-switch").returncode == 0:
            print(f"{vm}'s switch to its own configuration failed", file=sys.stderr)
            return 1

    reached = harness.wait_for(downstream, PROBE, f"{PROBE_NAME} through {netvm}",
                               NETWORK_DEADLINE)
    firewall = harness.ssh(netvm, "systemctl is-active --quiet qubes-firewall")
    if reached and firewall.returncode == 0:
        problems = []

        # The gate opened only once the netvm ran its own configuration. Read before the
        # daemon is stopped below, which closes the gate and reopens it with a new time.
        order = harness.ssh(netvm, GATE_AFTER_SWITCH)
        if order.returncode != 0:
            problems.append(f"{netvm}'s forwarding gate did not open after its switch to "
                            f"its own configuration: {order.stdout.strip()}")

        # Forwarding forced back on while the daemon is stopped, so what cuts the
        # downstream off has to be the gate, not ip_forward.
        stopped = harness.ssh(netvm, "sudo systemctl stop qubes-firewall && "
                                     "echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward")
        fetched = harness.ssh(downstream, FETCH)
        restarted = harness.ssh(netvm, "sudo systemctl start qubes-network")
        if stopped.returncode != 0 or restarted.returncode != 0:
            print(f"could not stop and restart {netvm}'s firewall daemon: "
                  f"{stopped.stderr.strip()} {restarted.stderr.strip()}", file=sys.stderr)
            return 1
        if fetched.returncode == 0:
            problems.append(f"{downstream} still reached {PROBE_NAME} through {netvm} with "
                            "its firewall daemon stopped and ip_forward on, so nothing was "
                            "applying its rules")
        elif fetched.returncode not in CUT_OFF:
            problems.append(f"could not tell whether {downstream} lost the network: the "
                            f"fetch exited {fetched.returncode}: {fetched.stderr.strip()}")

        if not problems:
            print(f"{downstream} reaches the network through {netvm} once {netvm} runs its "
                  "own configuration, and loses it while the firewall daemon is stopped, "
                  "ip_forward or not")
            return 0
        for problem in problems:
            print(problem, file=sys.stderr)
        return 1

    states = harness.ssh(netvm, "systemctl is-active " + " ".join(UNITS))
    if reached:
        print(f"{downstream} reached {PROBE_NAME} through {netvm}, but {netvm}'s firewall "
              "daemon is not running, so nothing applies its rules. Its netvm units are:",
              file=sys.stderr)
    else:
        print(f"{downstream} could not reach {PROBE_NAME} through {netvm}, whose netvm "
              "units are:", file=sys.stderr)
    for unit, state in zip(UNITS, states.stdout.split()):
        print(f"  {unit}: {state}", file=sys.stderr)
    if not states.stdout.strip():
        print(f"  unknown: {states.stderr.strip()}", file=sys.stderr)
    log = harness.ssh(netvm, "journalctl -b -u qubes-firewall --no-pager -o cat | tail -n 5")
    for line in log.stdout.splitlines():
        print(f"  qubes-firewall: {line}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
