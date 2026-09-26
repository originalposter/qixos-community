# systemd resolves an ordering cycle by deleting a job from it and booting anyway, so a
# cycle costs a unit silently.
#
# This asks what systemd would do with the units as built. `systemd-broke-no-cycles-at-boot`
# asks what it did.
{ config, pkgs, ... }:
{
  qixosTests.tests.systemd-has-no-ordering-cycles = pkgs.writeShellApplication {
    name = "systemd-has-no-ordering-cycles";
    # The nube's own systemd, not pkgs.systemd: NixOS builds its own variant, and this
    # should read the units with what will boot them.
    runtimeInputs = [ config.systemd.package pkgs.gnugrep ];
    text = ''
      # Unpinned, systemd-analyze resolves part of the graph and finds part of the
      # cycles: 2 against 18 where this was written.
      export SYSTEMD_UNIT_PATH=/etc/systemd/system

      # It also exits non-zero for warnings that are not cycles.
      found=$(systemd-analyze verify /etc/systemd/system/multi-user.target 2>&1 |
        grep -E "ordering cycle|deleted to break" || true)

      if [ -n "$found" ]; then
        echo "systemd would break ordering cycles in this nube's units:" >&2
        printf '%s\n' "$found" >&2
        exit 1
      fi

      echo "no ordering cycles in the unit set"
    '';
  };
}
