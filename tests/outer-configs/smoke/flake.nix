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
          };
          localFlake = {
            # Relative, so it resolves against the git root of this repo and that
            # whole root is what gets shipped to the nube.
            path = "./tests/nubes/smoke";
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
          properties = {
            label = "red";
            netvm = "sys-net";
            memory = 600;
          };
          localFlake = {
            path = "./tests/nubes/smoke";
            output = "qixosAppConfigurations.smoke";
          };
          deleteOnRemoval = true;
        };
      };
    };
  };
}
