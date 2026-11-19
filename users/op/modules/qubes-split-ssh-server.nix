{ pkgs, lib, config, ... }:
let
  cfg = config.qubesSplitSshServer;
  name = "qubes.SshAgent";
  qubesSplitSshServerScript = pkgs.writeShellApplication {
    name = "${name}";
    text = ''
      ${pkgs.socat}/bin/socat STDIO "UNIX-CONNECT:$SSH_AUTH_SOCK"
    '';
  };
  qubesSplitSshServer = pkgs.runCommand "${name}" {} ''
    mkdir -p $out/etc/qubes-rpc
    cp ${qubesSplitSshServerScript}/bin/${name} $out/etc/qubes-rpc/${name}
  '';
in
{
  options.qubesSplitSshServer = {
    enable = lib.mkEnableOption "qubes split SSH agent server";

    keyDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/home/${config.services.qubes.core.username}/.ssh/keys" ];
      defaultText = lib.literalExpression ''[ "/home/''${config.services.qubes.core.username}/.ssh/keys" ]'';
      description = "Directories whose keys ask before every use.";
    };

    autoKeyDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "/home/user/.ssh/keys" ];
      description = "Directories whose keys sign without asking, for a vault serving something unattended. Empty by default, so no key signs unasked unless a config says so.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.ssh.startAgent = true;
    programs.ssh.enableAskPassword = true;
    
    services.qubes.qrexec.packages = [ qubesSplitSshServer ];
    
    systemd.user.services.ssh-add-keys = {
      description = "Add SSH keys to agent";
      wantedBy = [ "default.target" ];
      after = [ "ssh-agent.service" ];
      requires = [ "ssh-agent.service" ];
      serviceConfig = {
        Type = "oneshot";
        # A key that signs without asking signs for anyone dom0 policy lets use the
        # vault, so keep autoKeyDirs to the keys meant for that.
        ExecStart = pkgs.writeShellScript "ssh-add-keys" ''
          add() {
            for key in "$1"/*; do
              [[ -e "$key" && "$key" != *.pub ]] || continue
              ${pkgs.openssh}/bin/ssh-add "''${@:2}" "$key"
            done
          }
          ${lib.concatMapStrings (d: "add ${lib.escapeShellArg d} -c
") cfg.keyDirs}
          ${lib.concatMapStrings (d: "add ${lib.escapeShellArg d}
") cfg.autoKeyDirs}
        '';
        Environment = "SSH_AUTH_SOCK=%t/ssh-agent";
      };
    };
  };
}
