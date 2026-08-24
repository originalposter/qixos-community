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

    sshServer = [
      opQixCommunity.nixosModules.modules.qubes-ssh-server
      {
        qubesSshServer = {
          enable = true;
          authorizedKeys = [ adminKey ];
        };
      }
    ];
  in
  {
    # The template runs sshd too, so the runner can read its host keys and check that
    # none of them turned up in an AppVM. Without keys of its own the template gives
    # that test nothing to find.
    qixosTemplateConfigurations.smoke = qixCore.lib.mkNubeTemplate { inherit nixpkgs; } {
      modules = sshServer ++ sharedModules;
    };

    qixosAppConfigurations.smoke = qixCore.lib.mkNubeApp {
      # So the config can be evaluated on its own, which is how a test asserts that
      # it contains what it declared rather than merely that it evaluates.
      directBuild = { inherit nixpkgs; };

      modules = sshServer ++ sharedModules;
    };

    # In this flake rather than one of its own so it joins the smoke cluster: an AppVM
    # shares its template's store, and a separate flake would mean a second template to
    # clone and rebuild on every run for no isolation this needs. The tests it carries
    # only touch its own clipboard.
    qixosAppConfigurations.password = qixCore.lib.mkNubeApp {
      directBuild = { inherit nixpkgs; };

      modules = [
        opQixCommunity.nixosModules.modules.password-menu.receiver
        # Both halves in one nube. They are not wired to each other: the menu's tests
        # stand in for qrexec rather than calling across, so this costs a build and
        # saves a second qube.
        opQixCommunity.nixosModules.modules.password-menu.menu
        {
          qubesPasswordMenu.enable = true;
        }
        {
          # Short timers because two of these tests wait out a timeout. The tests read
          # these same options, so they follow whatever is set here.
          #
          # clearSeconds is not as short as it could be. Tests that wait for the handover
          # wait half of it and then have to get their remaining requests in before it
          # expires, and each of those is a fresh process, which this nube is slower at
          # than it looks.
          qubesPasswordReceiver = {
            enable = true;
            pasteTimeoutSeconds = 5;
            clearSeconds = 6;
          };

          qixosTests.enable = true;
        }
      ] ++ sshServer ++ sharedModules;
    };

    # Two of these are created from the outer config, and the ssh host key tests use
    # them as a pair: one is rebooted to see whether it keeps its keys, and the two are
    # compared against each other and against their template. Nothing but sshd, so a
    # failure is about host keys and not about whatever else a nube was carrying.
    #
    # Their own cluster is not worth the second template build. They share the smoke
    # template, which is the arrangement under test anyway: a shared root volume is
    # exactly where an inherited host key would come from.
    qixosAppConfigurations.sshIdentity = qixCore.lib.mkNubeApp {
      directBuild = { inherit nixpkgs; };

      modules = sshServer ++ sharedModules;
    };

    nixosConfigurations.template = self.qixosTemplateConfigurations.smoke.nixosConfigurations.default;
    nixosConfigurations.smoke = self.qixosAppConfigurations.smoke.nixosConfigurations.default;
    nixosConfigurations.password = self.qixosAppConfigurations.password.nixosConfigurations.default;
    nixosConfigurations.ssh-identity = self.qixosAppConfigurations.sshIdentity.nixosConfigurations.default;
  };
}
