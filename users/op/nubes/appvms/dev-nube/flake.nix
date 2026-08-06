{
  description = ''
    general nube cluster
    '';

  inputs = {

    nixpkgs.url = "nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code-third-party = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    opQixCommunity = {
      url = "path:../../../";
    };

    qixCore = {
      url = "git+https://github.com/originalposter/qixos?ref=master";
    };

  };

  outputs = { self, nixpkgs, home-manager, nixvim, claude-code-third-party, opQixCommunity, qixCore, ... }:
  {
    qixosAppConfigurations.default = qixCore.lib.mkNubeApp {
      directBuild = {
        inherit nixpkgs;
      };

      specialArgs = {
        inherit self;
      };

      modules = [
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            # useGlobalPkgs so the overlay and allowUnfreePredicate set below also apply to
            # the home configuration; useUserPackages so home packages land in
            # /etc/profiles/per-user, where the qubes appmenus job looks for .desktop files.
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = { inherit nixvim; };
            users.user.imports = [ ./dev.nix ];
          };
        }

        ({ lib, pkgs, ... }: {
          nixpkgs.overlays = [ claude-code-third-party.overlays.default ];

          nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
           "claude-code"
          ];

          # Nix lsp and formatter
          environment.systemPackages = with pkgs; [
            claude-code
            nixd
            alejandra
            age
            wget
            home-manager.packages.${pkgs.system}.home-manager
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

          # FIXME: The reason we mkForce here is because the shell in the original nixos template code
          # imported as a qubes-nixos-template module sets the shell as bash.
          # We should sort out that code.
          users.users.user.shell = lib.mkForce pkgs.zsh;
          programs.zsh.enable = true;
          programs.gnupg.agent = {
            enable = true;
            pinentryPackage = pkgs.pinentry-curses;
          };
        })
      ] ++ [ opQixCommunity.nixosModules.modules.qubes-split-ssh-client
        ({ lib, ... }: { qubesSplitSsh = { enable = true; vaultName = lib.mkDefault "split-ssh-nube"; }; })
        opQixCommunity.nixosModules.modules.blueprints.basic-template ];
    };

    nixosConfigurations.default = self.qixosAppConfigurations.default.nixosConfigurations.default;
  };
}
