{
  inputs = {
  };
  
  outputs = { ... }:
  let
    prefix = "";
    suffix = "-nube";
    branch = "remove-hm-privilege";
    adminName = "qixos-admin";
    repoPath = "git+https://github.com/originalposter/qixos-community?ref=${branch}";
  in {
    # qixosConfigurations describes the qubes part of the qixOS configuration.
    # It contains a set of nix qubes (nubes) clusters. Each cluster contains
    # 1 template and a set of app VMs that depend on that template.
    # This configuration only describes the VM specific parts of the nubes.
    # It does not contain the configuration that is applied *inside* of the VM.
    # That part is relegated to the configuration pointed to by the `flakeUrl`
    # field of the cluster template.
    qixosConfigurations.testy = {
      # The qubes tag which signifies the qube is managed by the qixos-rebuild runner
      # recommended is `created-by-<qixos-rebuild runner name>` since this is automatically
      # set by qubes on any qube created by this qube and is unforgeable
      managementTag = "created-by-${adminName}";
      # Name of the template to clone when creating new templates.
      # It is not very important which qube this is since it will run `nixos-rebuild switch`
      # and completely overwrite its own config. However it will keep cached things in /nix/store
      # until those are cleaned up.
      #
      # It is important that it has the `managementTag` attached to it.
      baseTemplate = "${adminName}-base-template";

      nubeClusters."${prefix}template-test${suffix}" = {
        template = {
          properties = {
            label = "red";
          };
          localFlake = {
            path = "./users/op/nubes/appvms/test";
            output = "qixosTemplateConfigurations.test";
          };
          deleteOnRemoval = true;
        };

        appVms."${prefix}test${suffix}" = {
          properties = {
            label = "red";
            netvm = "sys-net";
          };
          localFlake = {
            path = "./users/op/nubes/appvms/test";
            output = "qixosAppConfigurations.test";
          };
          deleteOnRemoval = true;
        };

        appVms."${prefix}test-remote${suffix}" = {
          properties = {
            label = "red";
            netvm = "sys-net";
          };
          remoteFlake = {
            url = "${repoPath}&dir=users/op/nubes/appvms/test";
            output = "qixosAppConfigurations.test";
          };
          deleteOnRemoval = true;
        };

        appVms."${prefix}discord${suffix}" = {
          properties = {
            label = "red";
            netvm = "sys-net";
          };

          remoteFlake = {
            url = "${repoPath}&dir=users/op/nubes/appvms/discord";
            output = "qixosAppConfigurations.discord-nube";
          };
          deleteOnRemoval = true;
        };

      };

    };
  };
}
