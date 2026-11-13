# basic-template points git's ssh command at the qubes-git-client wrapper, for every
# nube. A wrapper that cannot be handed a port takes every ordinary remote with it: this
# nube's own `git pull` from a forge on 2222 is what broke when the wrapper was declared
# `ssh.variant = simple`.
#
# Only the one failure that happened: git refusing a port before the wrapper runs at
# all. What the wrapper does with a `.qube` host needs qrexec and belongs elsewhere.
{ pkgs, ... }:
{
  qixosTests.tests.git-reaches-a-host-with-a-port = pkgs.writeShellApplication {
    name = "git-reaches-a-host-with-a-port";
    runtimeInputs = [ pkgs.git pkgs.gnugrep ];
    text = ''
      # Nothing listens on this, so the only question is whether git gets as far as
      # trying. A variant that cannot carry a port fails before the connection.
      out=$(git ls-remote ssh://127.0.0.1:2222/nothing 2>&1 || true)

      if grep -qi "does not support setting port" <<<"$out"; then
        echo "git cannot use a port with this nube's ssh command:" >&2
        printf '%s\n' "$out" >&2
        exit 1
      fi
    '';
  };
}
