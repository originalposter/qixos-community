# Client half of the qrexec ssh tunnel. Teaches ssh to reach a qube by name, by
# routing any host ending in `.qube` through the target's `qubes.Ssh` qrexec service
# instead of the network. Pair with qubes-ssh-server.nix on the target.
#
#   ssh vault.qube
#   ssh vault.qube systemctl is-system-running
#   scp notes.txt vault.qube:/tmp/
#   rsync -e ssh -a ./src/ vault.qube:/home/user/src/
#
# An ssh_config block rather than a wrapper: ssh's remote command is positional and
# option parsing stops at the destination, so a wrapper injecting its own flags cannot
# leave room for both.
#
# The qube running this needs a dom0 policy line naming it as the source, in a file
# under /etc/qubes/policy.d/:
#
#   qubes.Ssh * <client-qube> <target-qube> allow
#
# A tag can stand in for the target, which keeps one line covering a whole set of
# qubes without naming each:
#
#   qubes.Ssh * <client-qube> @tag:<tag> allow
#
# Authentication is by key: generate one on the client (`ssh-keygen -t ed25519`) and
# put the public half in the target's `qubesSshServer.authorizedKeys`. ~/.ssh lives
# under /home, which is bound from /rw (qixos core.nix), so the key survives reboots
# even in an AppVM.
#
# Host keys are checked with `accept-new`: a first connection is recorded and a later
# change fails hard. There is no network path to interpose on here, so this is not
# about interception - it is that qube names are reusable, and removing a qube and
# creating another under the same name would otherwise go unnoticed.
{ pkgs, lib, config, ... }:
let
  cfg = config.qubesSshClient;

  # A script rather than inline shell: ssh runs ProxyCommand through `sh -c`, so
  # stripping the suffix there would mean nesting another one.
  sshProxy = pkgs.writeShellApplication {
    name = "qubes-ssh-proxy";
    runtimeInputs = [ pkgs.qubes-core-qrexec ];
    text = ''
      if [ "$#" -ne 1 ]; then
        echo "usage: qubes-ssh-proxy <host>" >&2
        exit 2
      fi
      # ssh passes the host as written, e.g. "admin.${cfg.hostSuffix}".
      exec qrexec-client-vm "''${1%.${cfg.hostSuffix}}" ${cfg.serviceName}
    '';
  };

  # Brings its own indentation: nix inserts interpolated values verbatim.
  identityLines = lib.optionalString (cfg.identityFile != null)
    "  IdentityFile ${cfg.identityFile}\n  IdentitiesOnly yes\n";
in
{
  options.qubesSshClient = {
    enable = lib.mkEnableOption "reaching qubes over qrexec with ssh";

    hostSuffix = lib.mkOption {
      type = lib.types.str;
      default = "qube";
      description = ''
        Hostname suffix that marks a destination as a qube to reach over qrexec.
        `ssh foo.qube` contacts the qube named `foo`. A suffix is needed so the
        ssh_config block cannot match real hosts.
      '';
    };

    serviceName = lib.mkOption {
      type = lib.types.str;
      default = "qubes.Ssh";
      description = ''
        qrexec service to dial on the target. Must match the target's
        `qubesSshServer.serviceName` and the dom0 policy line.
      '';
    };

    remoteUser = lib.mkOption {
      type = lib.types.str;
      default = "user";
      description = "default account to log in as, overridable per invocation as usual";
    };

    identityFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/user/.ssh/id_ed25519_qubes";
      description = ''
        Private key to present, for keys not named one of ssh's defaults. A path
        rather than the key itself: private material must not reach the nix store,
        which is world readable and shared across a whole nube cluster.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # NixOS places extraConfig ahead of its own `Host *` block, and ssh_config takes
    # the first value seen for each keyword, so these win for matching hosts without
    # affecting anything else.
    programs.ssh.extraConfig = ''
      Host *.${cfg.hostSuffix}
        User ${cfg.remoteUser}
        ProxyCommand ${sshProxy}/bin/qubes-ssh-proxy %h
        StrictHostKeyChecking accept-new
      ${identityLines}'';
  };
}
