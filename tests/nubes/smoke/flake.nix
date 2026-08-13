{
  description = ''
    Smoke test cluster: the smallest nube the suite can assert against.

    Deliberately minimal. Every package here is one the test has to build and every
    module is one that can break for reasons unrelated to what is under test.
    '';

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    # Deeper than the nubes under users/op, which reach it as `../../../`.
    opQixCommunity = {
      url = "path:../../../users/op";
    };

    # TODO: go back to master when appropriate
    qixCore = {
      url = "git+https://github.com/originalposter/qixos?ref=unstable";
    };
  };

  outputs = { self, nixpkgs, opQixCommunity, qixCore, ... }:
  let
    # The runner reaches nubes as qixos-admin-test, so this is that qube's key.
    adminKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKGEbNDM5L7K4wY8CWsvY72UflD7k44Ym3C5uMy6ydBE qixos-admin-test";

    sharedModules = [ opQixCommunity.nixosModules.modules.blueprints.basic-template ];
  in
  {
    qixosTemplateConfigurations.smoke = qixCore.lib.mkNubeTemplate { inherit nixpkgs; } {
      modules = sharedModules;
    };

    qixosAppConfigurations.smoke = qixCore.lib.mkNubeApp {
      # So the config can be evaluated on its own, which is how a test asserts that
      # it contains what it declared rather than merely that it evaluates.
      directBuild = { inherit nixpkgs; };

      modules = [
        # Only in the AppVM's modules, not the template's. Reaching this nube over
        # ssh therefore depends on the switch having run, and a test that plants a
        # fixture here is not silently satisfied by the template's own config.
        opQixCommunity.nixosModules.modules.qubes-ssh-server
        {
          qubesSshServer = {
            enable = true;
            authorizedKeys = [ adminKey ];
          };
        }
      ] ++ sharedModules;
    };

    nixosConfigurations.template = self.qixosTemplateConfigurations.smoke.nixosConfigurations.default;
    nixosConfigurations.smoke = self.qixosAppConfigurations.smoke.nixosConfigurations.default;
  };
}
