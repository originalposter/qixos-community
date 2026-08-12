# SSH access into a qube, carried over qrexec instead of the network.
#
# sshd listens on loopback only and a qrexec service pipes stdio to it, so the
# listener is unreachable from the netvm or the LAN even when the qube has one. dom0
# policy is the thing that decides who may connect. Pair with qubes-ssh-client.nix,
# which documents the policy line.
#
# Off by default, and worth leaving off unless a qube specifically needs remote
# access: qixos core puts the primary account in `wheel` with passwordless sudo
# (core.nix), so anyone dom0 policy admits effectively has root in the qube.
{ pkgs, lib, config, ... }:
let
  cfg = config.qubesSshServer;
  user = config.services.qubes.core.username;

  # Named `qubes.Ssh` because that is what the widely documented Qubes
  # ssh-over-qrexec recipe uses, so one dom0 policy line can cover qixos nubes and
  # ordinary qubes alike.
  sshdServiceScript = pkgs.writeShellApplication {
    name = cfg.serviceName;
    text = ''
      exec ${pkgs.socat}/bin/socat STDIO "TCP:127.0.0.1:${toString cfg.port}"
    '';
  };

  sshdService = pkgs.runCommand cfg.serviceName {} ''
    mkdir -p $out/etc/qubes-rpc
    cp ${sshdServiceScript}/bin/${cfg.serviceName} $out/etc/qubes-rpc/${cfg.serviceName}
  '';
in
{
  options.qubesSshServer = {
    enable = lib.mkEnableOption "ssh access to this qube over qrexec";

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [ "ssh-ed25519 AAAAC3Nz... user@client-qube" ];
      description = ''
        Public keys permitted to log in as the primary account. There is no default
        on purpose: an sshd with no keys accepts nobody, which fails in a way that
        looks like a broken tunnel rather than a missing setting.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 22;
      description = "loopback port sshd binds and the qrexec service dials";
    };

    serviceName = lib.mkOption {
      type = lib.types.str;
      default = "qubes.Ssh";
      description = ''
        qrexec service name to expose. Must match the service named in the dom0
        policy line and in the client's `qubesSshClient.serviceName`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = cfg.authorizedKeys != [];
      message = "qubesSshServer.authorizedKeys is empty, so sshd would accept no logins. Set it to the public key of whoever should get in.";
    }];

    services.openssh = {
      enable = true;

      # Loopback only. The qrexec service above is the sole route in.
      listenAddresses = [{
        addr = "127.0.0.1";
        port = cfg.port;
      }];

      settings = {
        # qixos core sets the primary account's password to "" (core.nix), so
        # password auth being off is load bearing here, not just hygiene.
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitEmptyPasswords = false;
        PermitRootLogin = "no";
      };
    };

    users.users.${user}.openssh.authorizedKeys.keys = cfg.authorizedKeys;

    services.qubes.qrexec.packages = [ sshdService ];
  };
}
