{
  description = ''
    Outer config for the split password demo: a vault and a browser, owned by the test
    admin. Applied and driven by hand, not by the suite.

    dom0 needs a policy line before a password can cross, in a file under
    /etc/qubes/policy.d/. It cannot be installed from here, because dom0 policy is
    dom0's:

      qixos.PasswordPaste * test-demo-vault @tag:created-by-qixos-admin-test ask default_target=test-demo-browser

    The tag keeps the prompt's choices to qubes the test admin manages, so nothing in
    this demo can propose a secret into a production qube.

    Then, from a dom0 terminal:

      qvm-run test-demo-vault qixos-password-menu
      qvm-run test-demo-vault 'qixos-password-menu --with-username'

    The store is planted at first boot and holds `github.com+op@example.invalid`,
    `bank.example+1234567` and `wifi`. The last has no username, so `--with-username`
    refuses it rather than pasting a password into a username field.
    '';

  inputs = {
  };

  outputs = { ... }:
  let
    # Same convention as the smoke scenario: everything starts with `test-`, the
    # scenario name follows, so teardown can find its own work by prefix.
    prefix = "test-demo-";
    adminName = "qixos-admin-test";
  in {
    qixosConfigurations.demo = {
      managementTag = "created-by-${adminName}";
      baseTemplate = "${adminName}-base-template";

      nubeClusters."${prefix}template" = {
        template = {
          properties = {
            label = "black";
          };
          localFlake = {
            path = "./users/op/tests/nubes/demo";
            output = "qixosTemplateConfigurations.demo";
          };
        };

        appVms."${prefix}vault" = {
          properties = {
            label = "purple";
            # No network at all: the store and the gpg key live here, and the only way
            # anything leaves is the qrexec call dom0 has to approve.
            netvm = "none";
          };
          localFlake = {
            path = "./users/op/tests/nubes/demo";
            output = "qixosAppConfigurations.vault";
          };
          deleteOnRemoval = true;
        };

        appVms."${prefix}browser" = {
          properties = {
            label = "orange";
            netvm = "sys-net";
          };
          localFlake = {
            path = "./users/op/tests/nubes/demo";
            output = "qixosAppConfigurations.browser";
          };
          deleteOnRemoval = true;
        };
      };
    };
  };
}
