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
        ExecStart = pkgs.writeShellScript "ssh-add-keys" ''
          for key in $HOME/.ssh/keys/*; do
            [[ "$key" == *.pub ]] && continue
            ${pkgs.openssh}/bin/ssh-add -c "$key"
          done
        '';
        Environment = "SSH_AUTH_SOCK=%t/ssh-agent";
      };
    };
  };
}
