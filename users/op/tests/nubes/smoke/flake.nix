{
  description = ''
    Smoke test cluster: the smallest nube the suite can assert against.

    Deliberately minimal. Every package here is one the test has to build and every
    module is one that can break for reasons unrelated to what is under test.
    '';

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    opQixCommunity = {
      url = "path:../../..";
    };

    # TODO: go back to master when appropriate
    qixCore = {
      url = "git+https://github.com/originalposter/qixos?ref=unstable";
    };
  };

  outputs = { self, nixpkgs, opQixCommunity, qixCore, ... }:
  let
    # The runner reaches nubes as qixos-admin-test, so this is that qube's key.
    # FIXME: This should not be hard-coded - it should be provisioned somehow
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

    # In this flake rather than one of its own so it joins the smoke cluster: an AppVM
    # shares its template's store, and a separate flake would mean a second template to
    # clone and rebuild on every run for no isolation this needs. The tests it carries
    # only touch its own clipboard.
    qixosAppConfigurations.password = qixCore.lib.mkNubeApp {
      directBuild = { inherit nixpkgs; };

      modules = [
        opQixCommunity.nixosModules.modules.password-menu.receiver
        {
          # Short timers because two of these tests wait out a timeout. The tests read
          # these same options, so they follow whatever is set here.
          qubesPasswordReceiver = {
            enable = true;
            pasteTimeoutSeconds = 5;
            clearSeconds = 3;
          };

          qixosTests.enable = true;
        }

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
    nixosConfigurations.password = self.qixosAppConfigurations.password.nixosConfigurations.default;
  };
}
