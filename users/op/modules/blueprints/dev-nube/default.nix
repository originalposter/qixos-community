# Development nube configuration, shared by every nube that wants a working dev
# environment.
#
# A function of the flake inputs it needs rather than a plain module, because
# home-manager and nixvim both come from flake inputs and a module has no way to
# reach them. Call it from a flake's outputs:
#
#   (opQixCommunity.nixosModules.modules.blueprints.dev-nube {
#     inherit home-manager nixvim;
#   })
#
# LLM tooling lives in the llm-tools blueprint and language servers in the dev-lsp
# module, each imported alongside this one by the nubes that want it.
#
# The home-manager layer here is op's personal configuration (git identity, nixvim,
# shell). Anything wanting the tooling without the personal layer should take the
# system-level parts and leave `home-manager.users` alone.
{ home-manager, nixvim, opQixCommunity }:
{ lib, pkgs, ... }:
{
  imports = [
    home-manager.nixosModules.home-manager
    opQixCommunity.nixosModules.modules.qubes-split-ssh-client
    ({ lib, ... }: { qubesSplitSsh = { enable = true; vault = lib.mkDefault "split-ssh-nube"; }; })
  ];

  home-manager = {
    # useGlobalPkgs so the overlay and allowUnfreePredicate set below also apply to
    # the home configuration; useUserPackages so home packages land in
    # /etc/profiles/per-user, where the qubes appmenus job looks for .desktop files.
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit nixvim; };
    users.user.imports = [ ./home.nix ];
  };

  # The qubes agent leaves /etc/localtime dangling on NixOS, which crashes Lean's server.
  # TODO: fix this in core and drop it here. Whether a nube should see dom0's zone at all
  # is open, since passing it through leaks the host's time zone.
  time.timeZone = lib.mkDefault "UTC";

  environment.systemPackages = with pkgs; [
    # Nix formatter. nixd, the nix language server, is in the dev-lsp module.
    alejandra
    # Compilers. Their language servers are in dev-lsp.
    ghc
    cabal-install
    ocaml
    dune_3
    ocamlformat
    idris2
    lean4
    zig
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
    gh
    brave
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
