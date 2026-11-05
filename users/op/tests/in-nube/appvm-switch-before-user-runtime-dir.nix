# The AppVM's switch finished before the user's runtime directory came up.
#
# switch-to-configuration reloads the user units of every user logind lists, and takes
# /run/user/<uid> existing to mean that user's manager is running. It is created by
# user-runtime-dir@<uid>.service, which starts as soon as anything opens a session for the
# user (the console autologin on tty1 and hvc0, at boot), while user@<uid>.service is held back
# behind qixos-appvm-switch. In that window s-t-c finds the directory, has no bus to
# reload through, and exits 4 although the system side of the switch succeeded.
#
# The failure itself only shows when the session opens during the few hundred
# milliseconds s-t-c spends on its user step, about one boot in seven. The ordering this
# checks is what opens that window at all, and shows on every boot it is open in.
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
