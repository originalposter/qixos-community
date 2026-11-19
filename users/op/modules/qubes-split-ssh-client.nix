# Client half of split ssh: ssh-agent sockets in this nube whose every connection is a
# qubes.SshAgent call to a vault nube, which holds the keys and signs.
#
# Each vault's socket is named after it, /run/split-ssh/<vault>.sock, as the Qubes
# community split-ssh guide names its one socket after its vault. `vault` is the default:
# SSH_AUTH_SOCK names its socket, so ssh, git and anything else that asks the agent use
# it. `extraVaults` are used only by what is pointed at their sockets: an ssh `Host`
# block with `IdentityAgent /run/split-ssh/<vault>.sock`, or SSH_AUTH_SOCK set for one
# program. A vault's agent offers every key it holds, so keeping keys for different
# purposes in different vaults is what keeps clear which key a program is given.
{ pkgs, lib, config, ... }:
let
  cfg = config.qubesSplitSsh;

  dir = "/run/split-ssh";

  forward = unit: socket: vault: {
    "${unit}" = {
      description = "Split-ssh agent socket for ${vault}";
      wantedBy = [ "default.target" ];
      after = [ "systemd-tmpfiles-setup.service" ];
      serviceConfig = {
        Type = "simple";
        User = "user";
        ExecStartPre = "${pkgs.coreutils}/bin/rm -f ${socket}";
        ExecStart = ''
          ${pkgs.socat}/bin/socat \
            UNIX-LISTEN:${socket},fork,umask=0177 \
            EXEC:"${pkgs.qubes-core-qrexec}/bin/qrexec-client-vm ${vault} qubes.SshAgent"
        '';
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
in
{
  options.qubesSplitSsh = {
    enable = lib.mkEnableOption "qubes split ssh signing";

    vault = lib.mkOption {
      type = lib.types.str;
      description = "Vault nube asked for signatures by default, through SSH_AUTH_SOCK.";
    };

    extraVaults = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "split-ssh-auto-nube" ];
      description = "Further vault nubes, each with its own socket at /run/split-ssh/<vault>.sock.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Shared by every vault's service. A RuntimeDirectory would be removed whenever any
    # one of them stopped.
    systemd.tmpfiles.rules = [ "d ${dir} 0755 user user -" ];

    systemd.services = lib.mkMerge (map
      (vault: forward "qubes-split-ssh-agent-${vault}" "${dir}/${vault}.sock" vault)
      (lib.unique ([ cfg.vault ] ++ cfg.extraVaults)));

    environment.variables.SSH_AUTH_SOCK = "${dir}/${cfg.vault}.sock";
  };
}
