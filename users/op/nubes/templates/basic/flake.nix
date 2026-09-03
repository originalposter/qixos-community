{
  description = ''
    basic nube template
    '';

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    opQixCommunity = {
      url = "path:../../../";
    };

    qixCore = {
      url = "git+https://github.com/originalposter/qixos?ref=unstable";
    };
  };

  outputs = { self, nixpkgs, opQixCommunity, qixCore, ... }:
  {
    qixosTemplateConfigurations.default = qixCore.lib.mkNubeTemplate { inherit nixpkgs; } {
      modules = [ opQixCommunity.nixosModules.modules.blueprints.basic-template ];
    };

    nixosConfigurations.default = self.qixosTemplateConfigurations.default.nixosConfigurations.default;

  };
}
