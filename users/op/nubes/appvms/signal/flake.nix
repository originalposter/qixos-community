{
  description = ''
    general nube cluster
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
    qixosAppConfigurations.signal-nube = qixCore.lib.mkNubeApp {
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = with pkgs; [signal-desktop];
        })
        opQixCommunity.nixosModules.modules.blueprints.basic-template
      ];
    };

    nixosConfigurations.default = self.qixosAppConfigurations.signal-nube.nixosConfigurations.default;
  };
}
