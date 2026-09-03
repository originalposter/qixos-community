{
  description = ''
    QixOS management qube for the test suite.

    The production admin plus ssh access over qrexec, so a dev nube can drive it.
    Shares standalones/qixos-admin's configuration through the blueprints.qixos-admin
    module and adds only what differs.

    Do not point a production admin's QIXOS_ADMIN_FLAKE at this config. It runs an
    sshd, and qixos core puts the primary account in `wheel` with passwordless sudo,
    so a shell here is effectively root in this qube - which holds admin API rights
    over every nube carrying its management tag.

    Installs as a second admin by running install.sh with QIXOS_ADMIN_NAME and
    QIXOS_ADMIN_FLAKE pointed here; it gets its own base template and management tag,
    sharing nothing with the production admin.
    '';

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    opQixCommunity = {
      url = "path:../../../";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # TODO: go back to master when appropriate
    qixCore = {
      url = "git+https://github.com/originalposter/qixos?ref=unstable";
    };
  };

  outputs = { self, nixpkgs, qixCore, opQixCommunity, ... }:
  {
    qixosStandaloneConfigurations.default = qixCore.lib.mkNubeStandalone { inherit nixpkgs; } {
      modules = [
        ({ pkgs, ...}: {
          environment.systemPackages = with pkgs; [
            python3
          ];
        })

        (opQixCommunity.nixosModules.modules.blueprints.qixos-admin { inherit qixCore; })

        opQixCommunity.nixosModules.modules.qubes-ssh-server
        {
          qubesSshServer = {
            enable = true;
            authorizedKeys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHrgdgAPOL58FlemsViJsw3DCphpQXWLuiNMasXECwPO claude@dev-nube"
            ];
          };
        }

        # The client half too: the runner reaches into test nubes over the same
        # transport, so in-nube tests need no qrexec service of their own.
        opQixCommunity.nixosModules.modules.qubes-ssh-client
        { qubesSshClient.enable = true; }

        # No qubesSplitSsh here on purpose. The vault it would point at belongs to the
        # production cluster, and a test admin should not depend on anything outside
        # its own management tag.

        opQixCommunity.nixosModules.modules.blueprints.basic-template
      ];
    };

    nixosConfigurations.default = self.qixosStandaloneConfigurations.default.nixosConfigurations.default;
  };
}
