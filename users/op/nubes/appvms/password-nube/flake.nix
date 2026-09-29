{
  description = ''
     password-nube
    '';

  inputs = {
    opQixCommunity = {
      url = "path:../../../";
    };

    qixCore = {
      url = "git+https://github.com/originalposter/qixos?ref=refs/tags/v0.2.0";
    };
  };

  outputs = { self, opQixCommunity, qixCore, ... }:
  {
    qixosAppConfigurations.password-nube = qixCore.lib.mkNubeApp {
      modules = [
        opQixCommunity.nixosModules.modules.blueprints.password
        opQixCommunity.nixosModules.modules.blueprints.basic-template
      ];
    };
  };
}
