{
  description = ''
    review-nube: Forgejo. See modules/blueprints/forgejo.nix.
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

    opQixCommunity = {
      url = "path:../../../";
    };

    qixCore = {
      url = "git+https://github.com/originalposter/qixos?ref=refs/tags/v0.2.0";
    };
  };

  outputs = { self, home-manager, nixvim, opQixCommunity, qixCore, ... }:
  {
    qixosAppConfigurations.default = qixCore.lib.mkNubeApp {
      modules = [
        # Each qube reaching this Forgejo needs a dom0 policy line, in a file under
        # /etc/qubes/policy.d/, one per client qube:
        #
        #   qubes.ConnectTCP +3000 qixos-dev-nube review-nube allow
        opQixCommunity.nixosModules.modules.blueprints.forgejo
        {
          # git ignores a bare repo it only found by searching, so one committed inside a
          # checkout cannot run commands from its config.
          programs.git = {
            enable = true;
            config.safe.bareRepository = "explicit";
          };
        }
        (opQixCommunity.nixosModules.modules.blueprints.dev-nube {
          inherit home-manager nixvim opQixCommunity;
        })
        opQixCommunity.nixosModules.modules.blueprints.dev-lsp

        # Pushes to config-vault over ssh with op's split-ssh key, hence the agent.
        opQixCommunity.nixosModules.modules.qubes-ssh-client
        {
          qubesSshClient = {
            enable = true;
            useAgent = true;
          };
        }

        # Pasting a credential in here from the vault, the same way the browser nube
        # takes one. Needs a dom0 qixos.PasswordPaste line naming this qube.
        opQixCommunity.nixosModules.modules.qix-pw.receiver
        { qixPwReceiver.enable = true; }

        opQixCommunity.nixosModules.modules.blueprints.basic-template
      ];
    };
  };
}
