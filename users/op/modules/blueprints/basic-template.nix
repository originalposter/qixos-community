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
  programs.ssh.extraConfig = ''
    Host github.com
      HostName ssh.github.com
      Port 443
      ProxyCommand ${pkgs.netcat-openbsd}/bin/nc -X connect -x 127.0.0.1:8082 %h %p

    Host gitlab.com
      HostName ssh.gitlab.com
      Port 443
      ProxyCommand ${pkgs.netcat-openbsd}/bin/nc -X connect -x 127.0.0.1:8082 %h %p
  '';

  nixpkgs.hostPlatform = "x86_64-linux";
}
