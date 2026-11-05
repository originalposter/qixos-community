# The AppVM's switch finished before the user's runtime directory came up.
#
# switch-to-configuration takes /run/user/<uid> to mean a running user manager, so a
# directory created while user@<uid> waits on the switch makes it exit 4. That exit shows
# only on some boots; the ordering that allows it shows on every boot it is wrong in.
{ config, pkgs, ... }:
{
  qixosTests.tests.appvm-switch-before-user-runtime-dir = pkgs.writeShellApplication {
    name = "appvm-switch-before-user-runtime-dir";
    runtimeInputs = [ config.systemd.package pkgs.coreutils ];
    text = ''
      if [ -e /run/qubes/this-is-templatevm ]; then
        echo "a template has no switch of its own"
        exit 0
      fi

      uid=$(id -u user)
      switched=$(systemctl show -P ActiveEnterTimestampMonotonic qixos-appvm-switch.service)
      runtime_dir=$(systemctl show -P ActiveEnterTimestampMonotonic "user-runtime-dir@$uid.service")

      if [ "$switched" = 0 ]; then
        echo "qixos-appvm-switch.service never finished this boot" >&2
        exit 1
      fi
      if [ "$runtime_dir" != 0 ] && [ "$runtime_dir" -lt "$switched" ]; then
        echo "/run/user/$uid came up at $runtime_dir us, before the switch finished at $switched us" >&2
        exit 1
      fi

      echo "the switch finished at $switched us, the runtime dir came up at $runtime_dir us"
    '';
  };
}
