{
  description = ''
    QixOS management qube
    '';

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    opQixCommunity = {
      url = "path:../../../";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    qixCore = {
      url = "git+https://github.com/originalposter/qixos?ref=remove-hm-privilege";
    };
  };

  outputs = { self, nixpkgs, home-manager, qixCore, opQixCommunity, ... }:
  {

    qixosStandaloneConfigurations.default = qixCore.lib.mkNubeStandalone { inherit nixpkgs home-manager; } {
      modules = [
        {
          environment.systemPackages = [
            qixCore.packages.x86_64-linux.qubes-core-admin-client
            qixCore.packages.x86_64-linux.qixos-rebuild
            qixCore.packages.x86_64-linux.qvm-appmenus-stub
          ];
        }

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
