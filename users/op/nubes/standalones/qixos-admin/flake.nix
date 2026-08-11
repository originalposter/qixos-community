{
  description = ''
    QixOS management qube
    '';

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    opQixCommunity = {
      url = "path:../../../";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    qixCore = {
      url = "git+https://github.com/originalposter/qixos?ref=remove-hm-privilege";
    };
  };

  outputs = { self, nixpkgs, qixCore, opQixCommunity, ... }:
  {

    qixosStandaloneConfigurations.default = qixCore.lib.mkNubeStandalone { inherit nixpkgs; } {
      modules = [
        (opQixCommunity.nixosModules.modules.blueprints.qixos-admin { inherit qixCore; })

        opQixCommunity.nixosModules.modules.qubes-split-ssh-client
        {
          qubesSplitSsh = {
            enable = true;
            vaultName = "split-ssh-nube";
          };
        }

        opQixCommunity.nixosModules.modules.blueprints.basic-template
      ];
    };

    nixosConfigurations.default = self.qixosStandaloneConfigurations.default.nixosConfigurations.default;
  };
}
