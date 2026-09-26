# What systemd actually did, where `systemd-has-no-ordering-cycles` says what it would do.
# Catches cycles among units that only exist at runtime, from a generator or a drop-in.
#
# Ordering is computed before conditions, so a unit held back by ConditionPathExists still
# poisons the graph. That is why an AppVM fails this over a template-only unit.
{ config, pkgs, ... }:
{
  qixosTests.tests.systemd-broke-no-cycles-at-boot = pkgs.writeShellApplication {
    name = "systemd-broke-no-cycles-at-boot";
    # The nube's own systemd, not pkgs.systemd: NixOS builds its own variant, and this
    # should read the units with what will boot them.
    runtimeInputs = [ config.systemd.package pkgs.gnugrep ];
    text = ''
      found=$(journalctl -b 2>/dev/null |
        grep -E "ordering cycle|deleted to break" || true)

      if [ -n "$found" ]; then
        echo "systemd broke ordering cycles while booting this nube:" >&2
        printf '%s\n' "$found" >&2
        exit 1
      fi

      echo "no cycles broken this boot"
    '';
  };
}
