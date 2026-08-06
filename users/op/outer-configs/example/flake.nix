{
  inputs = {
  };
  
  outputs = { ... }:
  let
    # I like to use prefix and suffixes in my nube naming because it lets me easily copy a config for testing and quickly avoid all name clashes.
    prefix = "";
    # The -nube suffix lets me avoid confusion with regular non-QixOS qubes.
    suffix = "-nube";

    communityRepoAppvmUrl = "git+https://github.com/originalposter/qixos-community?ref=remove-hm-privilege&dir=users/op/nubes/appvms/";

    # I like to have a qixos-admin-test for testing things before I deploy them to my real system.
    # It is nice to be able to just change this one variable.
    adminName = "qixos-admin";
  in {
    # qixosConfigurations describes the qubes part of the qixOS configuration.
    # It contains a set of nix qubes (nubes) clusters. Each cluster contains
    # 1 template and a set of app VMs that depend on that template.
    # This configuration only describes the VM specific parts of the nubes.
    # It does not contain the configuration that is applied *inside* of the VM.
    # That part is relegated to the configuration pointed to by the `flakeUrl`
    # field of the cluster template.
    qixosConfigurations.example = {
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

      # In this config we just have 1 template which these nubes share.
      nubeClusters."${prefix}shared-template${suffix}" = {
        template = {
          properties = {
            label = "black";
          };
          # A local template is useful because it lets you update nixpkgs locally by doing `nix flake update` in the template directory and re-deploying.
          localFlake = {
            path = "./users/op/nubes/templates/basic";
            output = "qixosTemplateConfigurations.default";
          };

          deleteOnRemoval = true;
        };

        appVms."${prefix}browser${suffix}" = {
          properties = {
            label = "green";
          };

          remoteFlake = {
            url = "${communityRepoAppvmUrl}browser";
            output = "qixosAppConfigurations.default";
          };

          # Switching to a config which does not contain a "${prefix}browser${suffix}" nube we will delete this nube.
          deleteOnRemoval = true;
        };

        appVms."${prefix}documents${suffix}" = {
          properties = {
            label = "blue";
          };

          remoteFlake = {
            url = "${communityRepoAppvmUrl}documents";
            output = "qixosAppConfigurations.default";
          };
          deleteOnRemoval = false;
        };

      };

    };
  };
}
