{
  description = ''
     password-nube
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
    qixosAppConfigurations.password-nube = qixCore.lib.mkNubeApp {
      rootConfiguration = {
        modules = [
          ({ pkgs, ... }: {
            environment.systemPackages = with pkgs; [ gnupg pass keepassxc ];
	          programs.gnupg.agent = {
              enable = true;
              pinentryPackage = pkgs.pinentry-curses;
            };
          })
        ] ++ [ opQixCommunity.nixosModules.modules.blueprints.basic-template ];
      };
    };
  };
}
