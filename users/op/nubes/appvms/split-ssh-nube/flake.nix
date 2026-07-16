{
  description = ''
     split-ssh-nube
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
    qixosAppConfigurations.split-ssh-nube = qixCore.lib.mkNubeApp {
      rootConfiguration = {
        modules = [
          opQixCommunity.nixosModules.modules.qubes-split-ssh-server
          {
            qubesSplitSshServer.enable = true;
          }
        ] ++ [ opQixCommunity.nixosModules.modules.blueprints.basic-template ];
      };
    };
  };
}
