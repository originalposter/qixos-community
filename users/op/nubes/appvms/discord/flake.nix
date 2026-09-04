{
  description = ''
    discord nube for doing discord things
    '';

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    opQixCommunity = {
      url = "path:../../../";
    };

    qixCore = {
      url = "git+https://github.com/originalposter/qixos?ref=master";
    };
  };

  outputs = { self, qixCore, opQixCommunity, nixpkgs, home-manager, ... }:
  {
    qixosAppConfigurations.discord-nube = qixCore.lib.mkNubeApp {
      directBuild = {
        inherit nixpkgs;
      };

      modules = [
        # These belong at the nixos level rather than inside home-manager, because
        # useGlobalPkgs below makes home-manager reuse the nixos `pkgs`.
        ({ lib, ... }: {
          nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
             "discord-ptb-unwrapped"
             "discord-ptb"
          ];
          # Needed for vesktop to be compiled. The CVEs for this are not an issue in our case as far as I can tell.
          nixpkgs.config.permittedInsecurePackages = [ "pnpm-10.29.2" ];
        })

        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.user = { pkgs, ... }: {
              home.stateVersion = "24.05";
              home.packages = with pkgs; [
                discord-ptb
                webcord
              ];
              programs.vesktop = {
                enable = true;

                vencord.settings = {
                  autoUpdate = true;
                  autoUpdateNotification = true;
                  notifyAboutUpdates = true;

                  plugins = {
                    ClearURLs.enabled = true;
                    FixYoutubeEmbeds.enabled = true;
                  };
                };
              };
            };
          };
        }

        opQixCommunity.nixosModules.modules.blueprints.basic-template
      ];
    };

    nixosConfigurations.default = self.qixosAppConfigurations.discord-nube.nixosConfigurations.default;
  };
}
