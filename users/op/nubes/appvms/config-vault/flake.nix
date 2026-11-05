{
  description = ''
    config-vault-nube: serves qixos-community to other nubes. See
    modules/blueprints/config-vault.
  '';

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    opQixCommunity = {
      url = "path:../../../";
    };

    qixCore = {
      url = "git+https://github.com/originalposter/qixos?ref=refs/tags/v0.2.0";
    };
  };

  outputs = { self, opQixCommunity, qixCore, ... }:
  {
    qixosAppConfigurations.default = qixCore.lib.mkNubeApp {
      modules = [
        # dom0 policy, in a file under /etc/qubes/policy.d/. The realm reads, with the
        # repository as the argument, and the pusher is named. See
        # modules/qubes-git-client.nix.
        #
        #   qixos.ReadConfigVault +qixos-community @tag:created-by-qixos-admin config-vault-nube allow
        #   qubes.Ssh             *                review-nube                config-vault-nube allow
        #
        # The repos are created by hand, once, and this module serves what is there:
        #
        #   git init ~/config-vault/qixos-community
        opQixCommunity.nixosModules.modules.blueprints.config-vault

        # TODO: op's split-ssh public key. Empty leaves sshd off, so nothing can push.
        { configVault.pushKeys = [ ]; }

        opQixCommunity.nixosModules.modules.blueprints.basic-template
      ];
    };
  };
}
