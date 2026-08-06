{
  description = ''
    documents appvm
    '';

  inputs = {
    opQixCommunity = {
      url = "path:../../../";
    };

    qixCore = {
      url = "git+https://github.com/originalposter/qixos?ref=master";
    };
  };

  outputs = { self, opQixCommunity, qixCore, ... }:
  {
    qixosAppConfigurations.default = qixCore.lib.mkNubeApp {
      # TODO: Fill this with more useful documents management stuff
      rootConfiguration = {
        modules = [
          opQixCommunity.nixosModules.modules.blueprints.basic-template
        ];
      };
    };

    nixosConfigurations.default = self.qixosAppConfigurations.default.nixosConfigurations.default;
    homeConfigurations.default = self.qixosAppConfigurations.default.homeConfigurations.default;
  };
}
