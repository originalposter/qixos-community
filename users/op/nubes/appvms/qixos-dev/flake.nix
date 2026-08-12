{
  description = ''
    qixos development nube - the dev-nube environment plus the client side of the
    qrexec ssh tunnel, so it can reach the test admin and test nubes
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

    # TODO: go back to master when appropriate
    qixCore = {
      url = "git+https://github.com/originalposter/qixos?ref=remove-hm-privilege";
    };
  };

  outputs = { self, nixpkgs, home-manager, nixvim, claude-code-third-party, opQixCommunity, qixCore, ... }:
  {
    qixosAppConfigurations.default = qixCore.lib.mkNubeApp {
      # Direct build so this nube can be switched with nixos-rebuild while
      # iterating, without going through a cluster apply.
      directBuild = {
        inherit nixpkgs;
      };

      modules = [
        (opQixCommunity.nixosModules.modules.blueprints.dev-nube {
          inherit home-manager nixvim claude-code-third-party opQixCommunity;
        })

        opQixCommunity.nixosModules.modules.qubes-ssh-client
        {
          qubesSshClient = {
            enable = true;
            identityFile = "/home/user/.ssh/qixos-admin-test_ed25519";
          };
        }

        opQixCommunity.nixosModules.modules.blueprints.basic-template
      ];
    };

    nixosConfigurations.default = self.qixosAppConfigurations.default.nixosConfigurations.default;
  };
}
