# Development nube configuration, shared by every nube that wants a working dev
# environment.
#
# A function of the flake inputs it needs rather than a plain module, because
# home-manager, nixvim and the claude-code overlay all come from flake inputs and a
# module has no way to reach them. Call it from a flake's outputs:
#
#   (opQixCommunity.nixosModules.modules.blueprints.dev-nube {
#     inherit home-manager nixvim claude-code-third-party;
#   })
#
# The home-manager layer here is op's personal configuration (git identity, nixvim,
# shell). Anything wanting the tooling without the personal layer should take the
# system-level parts and leave `home-manager.users` alone.
{ home-manager, nixvim, claude-code-third-party }:
{ lib, pkgs, ... }:
{
  imports = [ home-manager.nixosModules.home-manager ];

  home-manager = {
    # useGlobalPkgs so the overlay and allowUnfreePredicate set below also apply to
    # the home configuration; useUserPackages so home packages land in
    # /etc/profiles/per-user, where the qubes appmenus job looks for .desktop files.
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit nixvim; };
    users.user.imports = [ ./home.nix ];
  };

  nixpkgs.overlays = [ claude-code-third-party.overlays.default ];

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "claude-code"
  ];

  environment.systemPackages = with pkgs; [
    claude-code
    # Nix lsp and formatter
    nixd
    alejandra
    age
    wget
    home-manager.packages.${pkgs.stdenv.hostPlatform.system}.home-manager
    gnumake
    pkg-config
    rustc
    cargo
    gcc
    nodejs
    postgresql
    docker
    docker-compose
    python3
    jq
    rofi
    dmenu
    curl
  ];

  # FIXME: The reason we mkForce here is because the shell in the original nixos
  # template code imported as a qubes-nixos-template module sets the shell as bash.
  # We should sort out that code.
  users.users.user.shell = lib.mkForce pkgs.zsh;
  programs.zsh.enable = true;
  programs.gnupg.agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-curses;
  };
}
