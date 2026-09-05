#!/usr/bin/env python3
"""A disposable boots the configuration of the nube it was disposed from.

A disposable's own name is generated at start and matches no qixos configuration, so the
switch job cannot look itself up the way an AppVM does. It resolves the name of the AppVM
it was made from instead, which QubesDB reports as `/qubes-base-template`.

The activation directory it reads is the template's, carried in on the root volume a
disposable shares with every other qube in the cluster, so what is asserted is that the
switch picked the right entry out of it rather than that the entry exists.

Failure before this worked was not silent: the job took its fallback branch and exited 1,
leaving the disposable running the template's system. That is what the two paths below
distinguish.

usage: dispvm_boots_its_appvm_config.py <dispvm-template>
"""
import sys

import harness

# Waits for the switch job to settle rather than assuming it beat this qrexec call. It
# runs `after default.target`, and a disposable answers qrexec well before then, so
# reading the system link straight away races it. `oneshot` with `RemainAfterExit` lands
# on active or failed, and failed is worth reporting rather than timing out on.
PROBE = """
for _ in $(seq 120); do
  state=$(systemctl show -p ActiveState --value qixos-appvm-switch 2>/dev/null)
  case "$state" in active|failed) break ;; esac
  sleep 1
done
echo "name=$(qubesdb-read /name 2>/dev/null)"
echo "base=$(qubesdb-read /qubes-base-template 2>/dev/null)"
echo "state=$state"
echo "current=$(readlink -f /run/current-system)"
echo "wanted=$(readlink -f /run/qixos/activation/%s/nixos)"
"""


def main(argv):
    if len(argv) != 2:
        print(f"usage: {argv[0]} <dispvm-template>", file=sys.stderr)
        return 2
    base = argv[1]

    result = harness.dispvm_run(base, PROBE % base)
    if result.returncode != 0:
        print(f"could not run in a disposable of {base}: {result.stderr.strip()}",
              file=sys.stderr)
        return 1

    fields = dict(
        line.split("=", 1) for line in result.stdout.splitlines() if "=" in line
    )
    name = fields.get("name", "")
    current = fields.get("current", "")
    wanted = fields.get("wanted", "")

    if not current or not wanted:
        print(f"a disposable of {base} reported no system paths: {result.stdout.strip()}",
              file=sys.stderr)
        return 1

    if fields.get("base") != base:
        print(f"a disposable of {base} names {fields.get('base')!r} as its base, so the "
              "switch had nothing it could have looked up", file=sys.stderr)
        return 1

    if current == wanted:
        print(f"{name} booted {base}'s configuration")
        return 0

    print(
        f"{name} is a disposable of {base} but is not running its configuration.\n"
        f"  switch job:  {fields.get('state', 'unknown')}\n"
        f"  running:     {current}\n"
        f"  should be:   {wanted}",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
