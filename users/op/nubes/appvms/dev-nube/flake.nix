{
  description = ''
    development nube
    '';

  inputs = {

    nixpkgs.url = "nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code-third-party = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    opQixCommunity = {
      url = "path:../../../";
    };

    qixCore = {
      url = "git+https://github.com/originalposter/qixos?ref=master";
    };

  };

  outputs = { self, nixpkgs, home-manager, nixvim, claude-code-third-party, opQixCommunity, qixCore, ... }:
  {
    qixosAppConfigurations.default = qixCore.lib.mkNubeApp {
      directBuild = {
        inherit nixpkgs;
      };

      modules = [
        (opQixCommunity.nixosModules.modules.blueprints.dev-nube {
          inherit home-manager nixvim claude-code-third-party opQixCommunity;
        })

        opQixCommunity.nixosModules.modules.blueprints.basic-template
      ];
    };

    nixosConfigurations.default = self.qixosAppConfigurations.default.nixosConfigurations.default;
  };
}
