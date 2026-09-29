{
  description = ''
     split-ssh-nube
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
    qixosAppConfigurations.split-ssh-nube = qixCore.lib.mkNubeApp {
      modules = [
        opQixCommunity.nixosModules.modules.qubes-split-ssh-server
        {
          qubesSplitSshServer.enable = true;
        }
      ] ++ [ opQixCommunity.nixosModules.modules.blueprints.basic-template ];
    };
  };
}
