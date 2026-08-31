{
  description = ''
    Outer config for the smoke scenario: one template, one AppVM, owned by the test
    admin. Applying this twice with no change between is the suite's first test.
    '';

  inputs = {
  };

  outputs = { ... }:
  let
    # Every qube the suite creates starts with `test-`, whatever the scenario, so a
    # name alone says whether a qube is disposable. The scenario name follows, so
    # teardown can identify its own work by prefix rather than by remembering what
    # it made.
    prefix = "test-smoke-";
    adminName = "qixos-admin-test";
  in {
    qixosConfigurations.smoke = {
      managementTag = "created-by-${adminName}";
      baseTemplate = "${adminName}-base-template";

      nubeClusters."${prefix}template" = {
        template = {
          properties = {
            label = "red";

            # Enough to evaluate every configuration in the cluster at once. An AppVM
            # takes its own memory from its template unless it sets one, so each below
            # says what it needs rather than inheriting this.
            memory = 2000;
          };
          localFlake = {
            # Relative, so it resolves against the git root of this repo and that
            # whole root is what gets shipped to the nube.
            path = "./users/op/tests/nubes/smoke";
            output = "qixosTemplateConfigurations.smoke";
          };

          # No deleteOnRemoval, unlike the AppVM below. Teardown would otherwise
          # discard the template and every run would pay for a fresh clone and a
          # full nixos-rebuild. Isolation survives the compromise because the AppVM
          # is still destroyed and recreated, and its root volume is a fresh
          # copy-on-write snapshot of the template each time. What is given up is
          # isolation of the template's own state between runs: a test that writes
          # to the template can poison later runs.
        };

        appVms."${prefix}nube" = {
          # Every value here differs from the qubes default on purpose. One that matches
          # proves nothing: apply would set nothing and the check would still pass.
          properties = {
            label = "red";
            netvm = "sys-net";
            memory = 1337;
            maxmem = 7331;
            vcpus = 3;
            autostart = true;
            includeInBackups = false;
            qrexecTimeout = 123;
            shutdownTimeout = 91;
          };
          localFlake = {
            path = "./users/op/tests/nubes/smoke";
            output = "qixosAppConfigurations.smoke";
          };
          deleteOnRemoval = true;
        };

        # Split password entry's destination half. Its tests need a running X session,
        # so unlike the nube above this one has to be started, not merely created.
        appVms."${prefix}password" = {
          properties = {
            label = "red";
            netvm = "none";
            memory = 400;
          };
          localFlake = {
            path = "./users/op/tests/nubes/smoke";
            output = "qixosAppConfigurations.password";
          };
          deleteOnRemoval = true;
        };

        # A pair for the ssh host key checks, which need two AppVMs of one cluster to
        # compare with each other and with their template. Two rather than reusing the
        # nubes above: the memory check destroys `${prefix}nube` when it finishes and
        # the password nube is rebooted by its own tests, so borrowing either would
        # make the order of CHECKS in `run` load bearing.
        #
        # No netvm. Nothing here reaches the network, and a host key test that could
        # would be a worse test.
        appVms."${prefix}ssh-a" = {
          properties = {
            label = "red";
            netvm = "none";
            memory = 400;
          };
          localFlake = {
            path = "./users/op/tests/nubes/smoke";
            output = "qixosAppConfigurations.sshIdentity";
          };
          deleteOnRemoval = true;
        };

        appVms."${prefix}ssh-b" = {
          properties = {
            label = "red";
            netvm = "none";
            memory = 400;
          };
          localFlake = {
            path = "./users/op/tests/nubes/smoke";
            output = "qixosAppConfigurations.sshIdentity";
          };
          deleteOnRemoval = true;
        };
      };
    };
  };
}
