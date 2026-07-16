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
      url = "git+https://codeberg.org/originalposter/qixos?ref=master";
    };
  };

  outputs = { self, qixCore, opQixCommunity, nixpkgs, home-manager, ... }:
  {
    qixosAppConfigurations.discord-nube = qixCore.lib.mkNubeApp {
      directBuild = {
        inherit nixpkgs home-manager;
      };

      homeConfiguration = {
        modules = [
        ({ lib, ... }:{
          nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
             "discord-ptb"
          ];
        })
        ({ pkgs, ... }:{
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
          # Needed for vesktop to be compiled. The CVEs for this are not an issue in our case as far as I can tell.
          nixpkgs.config.permittedInsecurePackages = [ "pnpm-10.29.2" ];
        }) ];
      };

      # Here you can place root configurations for this AppVM
      rootConfiguration = {
        modules = [ opQixCommunity.nixosModules.modules.blueprints.basic-template ];
      };
    };

    nixosConfigurations.default = self.qixosAppConfigurations.discord-nube.nixosConfigurations.default;
    homeConfigurations.default = self.qixosAppConfigurations.discord-nube.homeConfigurations.default;
  };
}
