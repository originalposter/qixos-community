{ pkgs, lib, config, ... }:
let
runtimedir = "split-ssh";
sockpath = "${runtimedir}/ssh-agent.sock";
in
{
  options.qubesSplitSsh = {
    enable = lib.mkEnableOption "qubes split ssh signing";

    vaultName = lib.mkOption {
      type = lib.types.str;
      description = "name of qube that will be asked to provide split ssh key signing";
    };
  };

  config = {
    systemd.services.qubes-split-ssh-agent = {
      description = "Qubes split-SSH agent proxy";
      wantedBy = [ "default.target" ];

      serviceConfig = {
        Type = "simple";
        User = "user";
        RuntimeDirectory = runtimedir;
        ExecStartPre = "${pkgs.coreutils}/bin/rm -f %t/${sockpath}";
        ExecStart = ''
          ${pkgs.socat}/bin/socat \
            UNIX-LISTEN:%t/${sockpath},fork,umask=0177 \
            EXEC:"${pkgs.qubes-core-qrexec}/bin/qrexec-client-vm ${config.qubesSplitSsh.vaultName} qubes.SshAgent"
        '';
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "5s";
      };

    };

    environment.variables.SSH_AUTH_SOCK = "/run/${sockpath}";
  };
}
