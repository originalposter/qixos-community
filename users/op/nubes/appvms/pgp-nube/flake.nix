{
  description = ''
    pgp-nube
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
  let
    splitGpg = opQixCommunity.nixosModules.modules.evq.packages.qubes-gpg-split.module;
  in
  {
    qixosAppConfigurations.pgp-nube = qixCore.lib.mkNubeApp {
      modules = [
        splitGpg

        ({pkgs, ...}: {
          environment.systemPackages = with pkgs; [ sequoia-sq ];
        })
      ] ++ [ opQixCommunity.nixosModules.modules.blueprints.basic-template ];
    };
  };
}
