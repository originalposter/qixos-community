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

  nixpkgs.hostPlatform = "x86_64-linux";
}
