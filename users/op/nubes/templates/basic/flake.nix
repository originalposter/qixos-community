{
  description = ''
    basic nube template
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

    ocQixCommunity = {
      url = "path:../../../";
    };

    qixCore = {
      url = "git+https://github.com/originalposter/qixos?ref=remove-hm-privilege";
    };
  };

  outputs = { self, nixpkgs, home-manager, ocQixCommunity, qixCore, ... }:
  {
    qixosTemplateConfigurations.default = qixCore.lib.mkNubeTemplate { inherit nixpkgs home-manager; } {
      modules = [ ocQixCommunity.nixosModules.modules.blueprints.basic-template ];
    };

    nixosConfigurations.default = self.qixosTemplateConfigurations.default.nixosConfigurations.default;

  };
}
