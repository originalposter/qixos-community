{ pkgs, ... }:
{
  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
    };
  };

  imports = [ ../st ];
  qixos-st.enable = true;

  hardware.graphics.enable = true;

  environment.systemPackages = with pkgs; [
    xfce4-terminal
    xterm
    neovim
    git
    ranger
  ];

  environment.variables = {
    EDITOR = "nvim";
  };

  # ssh has no proxy-environment support of any kind, so all_proxy does nothing
  # for it and a ProxyCommand is the only mechanism. Port 443 rather than 22
  # because the qubes updates proxy filters 22.
  #
  # Matched on being a template, since this blueprint is shared with the AppVMs and
  # dom0 grants qubes.UpdatesProxy to templates only. Unscoped, every AppVM sends its
  # ssh into a proxy that is not there. exec goes last so it only runs for these hosts.
  programs.ssh.extraConfig = ''
    Match host github.com,gitlab.com exec "test -e /run/qubes/this-is-templatevm"
      HostName ssh.%h
      Port 443
      ProxyCommand ${pkgs.netcat-openbsd}/bin/nc -X connect -x 127.0.0.1:8082 %h %p
  '';

  nixpkgs.hostPlatform = "x86_64-linux";
}
