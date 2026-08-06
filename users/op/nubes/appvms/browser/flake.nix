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
    qixosAppConfigurations.default = qixCore.lib.mkNubeApp {
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = with pkgs; [ brave ];
          programs.firefox.enable = true;
        })
        opQixCommunity.nixosModules.modules.qubes-split-ssh-client
        ({ lib, ... }: { qubesSplitSsh = { enable = true; vaultName = lib.mkDefault "split-ssh-nube"; }; })
        opQixCommunity.nixosModules.modules.blueprints.basic-template
      ];
    };

    nixosConfigurations.default = self.qixosAppConfigurations.default.nixosConfigurations.default;
  };
}
