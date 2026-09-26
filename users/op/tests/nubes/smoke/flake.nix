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
      url = "git+https://github.com/originalposter/qixos?ref=switch-oom-handling";
    };
  };

  outputs = { self, nixpkgs, opQixCommunity, qixCore, ... }:
  let
    # The runner reaches nubes as qixos-admin-test, so this is that qube's key.
    # FIXME: This should not be hard-coded - it should be provisioned somehow
    adminKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKGEbNDM5L7K4wY8CWsvY72UflD7k44Ym3C5uMy6ydBE qixos-admin-test";

    # Enabled here rather than per config, so any smoke test nube can be asked for its tests.
    sharedModules = [
      opQixCommunity.nixosModules.modules.blueprints.basic-template
      ../../in-nube
      { qixosTests.enable = true; }
    ];

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
    #
    # Its unit set is not the AppVMs': it carries the switch machinery and units gated on
    # being a template, so it is worth testing separately.
    qixosTemplateConfigurations.smoke = qixCore.lib.mkNubeTemplate { inherit nixpkgs; } {
      modules = sshServer ++ sharedModules;
    };

    qixosAppConfigurations.smoke = qixCore.lib.mkNubeApp {
      # So the config can be evaluated on its own, which is how a test asserts that
      # it contains what it declared rather than merely that it evaluates.
      directBuild = { inherit nixpkgs; };

      modules = sshServer ++ sharedModules;
    };

    # One nube whose configuration is expensive to evaluate, so a template with too
    # little memory is killed while evaluating it rather than thrashing for ten minutes.
    #
    # The cost is deliberately in evaluation and not in building. Each `environment.etc`
    # entry is a submodule, so the module system evaluates a full fixpoint per entry,
    # and `enable = false` drops every one of them before anything is written. That
    # leaves the evaluator's memory as the only thing that grows.
    #
    # One heavy nube rather than many ordinary ones on purpose. A cluster's evaluation
    # cost is the sum of its nubes only while they are evaluated together; a single
    # nube's is irreducible, so this keeps provoking a kill even if nubes are later
    # built one at a time.
    #
    # ENTRIES wants tuning against a real run, the same way the template's memory does.
    qixosAppConfigurations.oomHeavy = qixCore.lib.mkNubeApp {
      modules = sharedModules ++ [
        ({ lib, ... }: {
          environment.etc = builtins.listToAttrs (builtins.genList (i: {
            name = "qixos-oom-filler/${toString i}";
            value = { enable = false; text = toString i; };
          }) 20000);
        })
      ];
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

        }
      ] ++ sshServer ++ sharedModules;
    };

    # The split-gpg backend, whose tests call it from inside itself with the qrexec hop
    # stood in for. Sharing the smoke cluster for the same reason the password nube
    # does: what a second template would buy is isolation these tests do not need.
    #
    # `gnupg` because the tests generate a key and verify a signature with an ordinary
    # gpg, which is a different copy from the pinned one the qrexec services carry.
    # They share only ~/.gnupg, which is all they need to.
    qixosAppConfigurations.gpg = qixCore.lib.mkNubeApp {
      directBuild = { inherit nixpkgs; };

      modules = [
        opQixCommunity.nixosModules.modules.evq.packages.qubes-gpg-split.server
        ({ pkgs, ... }: {
          qubes.gpgSplitServer.enable = true;

          environment.systemPackages = [ pkgs.gnupg ];
        })
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
    nixosConfigurations.gpg = self.qixosAppConfigurations.gpg.nixosConfigurations.default;
  };
}
