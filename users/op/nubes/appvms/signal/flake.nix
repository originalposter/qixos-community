{
  description = ''
    general nube cluster
    '';

  inputs = {
    opQixCommunity = {
      url = "path:../../../";
    };

    qixCore = {
      url = "git+https://codeberg.org/originalposter/qixos?ref=master";
    };
  };

  outputs = { self, opQixCommunity, qixCore, ... }:
  {
    qixosAppConfigurations.signal-nube = qixCore.lib.mkNubeApp {
      homeConfiguration = {
        modules = [ ({ pkgs, ... }: {
          home.packages = with pkgs; [signal-desktop];
        }) ];
      };
      rootConfiguration = {
        modules = [
          opQixCommunity.nixosModules.modules.blueprints.basic-template
        ];
      };
    };

    nixosConfigurations.default = self.qixosAppConfigurations.signal-nube.nixosConfigurations.default;
    homeConfigurations.default = self.qixosAppConfigurations.signal-nube.homeConfigurations.default;
  };
}
