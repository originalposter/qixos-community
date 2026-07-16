{
  inputs = {
  };
  
  outputs = { ... }:
  let
    prefix = "";
    suffix = "-nube";
  in {
    # qixosConfigurations describes the qubes part of the qixOS configuration.
    # It contains a set of nix qubes (nubes) clusters. Each cluster contains
    # 1 template and a set of app VMs that depend on that template.
    # This configuration only describes the VM specific parts of the nubes.
    # It does not contain the configuration that is applied *inside* of the VM.
    # That part is relegated to the configuration pointed to by the `flakeUrl`
    # field of the cluster template.
    qixosConfigurations.gaia = {
      # The qubes tag which signifies the qube is managed by the qixos-rebuild runner
      # recommended is `created-by-<qixos-rebuild runner name>` since this is automatically
      # set by qubes on any qube created by this qube and is unforgeable
      managementTag = "created-by-qixos-admin";
      # Name of the template to clone when creating new templates.
      # It is not very important which qube this is since it will run `nixos-rebuild switch`
      # and completely overwrite its own config. However it will keep cached things in /nix/store
      # until those are cleaned up.
      #
      # It is important that it has the `managementTag` attached to it.
      baseTemplate = "qixos-admin-base-template";

      # Big nube cluster
      nubeClusters."${prefix}general${suffix}" = {
        template = {
          properties = {
            label = "black";
          };
          remoteFlake = {
            url = "git+https://codeberg.org/originalposter/qixos-community?ref=master&dir=users/op/nubes/templates/basic";
            output = "qixosTemplateConfigurations.default";
          };
        };

        appVms."${prefix}dev${suffix}" = {
          properties = {
            label = "orange";
            netvm = "sys-net";
          };

          remoteFlake = {
            url = "git+https://codeberg.org/originalposter/qixos-community?ref=master&dir=users/op/nubes/appvms/dev-nube";
            output = "qixosAppConfigurations.default";
          };
        };

        appVms."${prefix}signal${suffix}" = {
          properties = {
            label = "green";
            netvm = "sys-net";
          };

          remoteFlake = {
            url = "git+https://codeberg.org/originalposter/qixos-community?ref=master&dir=users/op/nubes/appvms/signal";
            output = "qixosAppConfigurations.signal-nube";
          };
        };

        appVms."${prefix}browser${suffix}" = {
          properties = {
            label = "orange";
            netvm = "sys-net";
          };

          remoteFlake = {
            url = "git+https://codeberg.org/originalposter/qixos-community?ref=master&dir=users/op/nubes/appvms/browser";
            output = "qixosAppConfigurations.default";
          };
        };
      };

      nubeClusters."${prefix}template-secrets${suffix}" = {
        template = {
          properties = {
            label = "black";
          };

          remoteFlake = {
            url = "git+https://codeberg.org/originalposter/qixos-community?ref=master&dir=users/op/nubes/templates/basic";
            output = "qixosTemplateConfigurations.default";
          };
        };

        appVms."${prefix}password${suffix}" = {
          properties = {
            label = "purple";
            netvm = "none";
          };

          localFlake = {
            path = "users/op/nubes/appvms/password-nube";
            output = "qixosAppConfigurations.password-nube";
          };
        };

        appVms."${prefix}pgp${suffix}" = {
          properties = {
            label = "purple";
            netvm = "none";
          };

          remoteFlake = {
            url = "git+https://codeberg.org/originalposter/qixos-community?ref=master&dir=users/op/nubes/appvms/pgp-nube";
            output = "qixosAppConfigurations.pgp-nube";
          };
        };

        appVms."${prefix}split-ssh${suffix}" = {
          properties = {
            label = "purple";
            netvm = "none";
          };

          remoteFlake = {
            url = "git+https://codeberg.org/originalposter/qixos-community?ref=master&dir=users/op/nubes/appvms/split-ssh-nube";
            output = "qixosAppConfigurations.split-ssh-nube";
          };
        };

      };

      # Small nube cluster with non-free software
      nubeClusters."${prefix}unfree-software-template${suffix}" = {
        template = {
          properties = {
            label = "red";
          };
          remoteFlake = {
            url = "git+https://codeberg.org/originalposter/qixos-community?ref=master&dir=users/op/nubes/templates/basic";
            output = "qixosTemplateConfigurations.default";
          };
        };

        appVms."${prefix}discord${suffix}" = {
          properties = {
            label = "red";
            netvm = "sys-net";
          };

          remoteFlake = {
            url = "git+https://codeberg.org/originalposter/qixos-community?ref=master&dir=users/op/nubes/appvms/discord";
            output = "qixosAppConfigurations.discord-nube";
          };
        };
      };

      standaloneNubes."${prefix}test-standalone${suffix}" = {
        properties = {
          label = "blue";
          netvm = "sys-net";
        };
        localFlake = {
          path = "users/op/nubes/appvms/test";
          output = "qixosTemplateConfigurations.test";
        };
      };

      nubeClusters."${prefix}template-test${suffix}" = {
        template = {
          properties = {
            label = "red";
          };

          localFlake = {
            path = "users/op/nubes/appvms/test";
            output = "qixosTemplateConfigurations.test";
          };
        };

        appVms."${prefix}test${suffix}" = {
          properties = {
            label = "red";
            netvm = "sys-net";
          };

          localFlake = {
            path = "users/op/nubes/appvms/test";
            output = "qixosAppConfigurations.test";
          };
        };
      };

      # FIXME: Currently does not support qixos-admin managing itself.
      # We'd need custom logic to detect self-management because qubes does not support a qrexec self-reference.
      #standaloneNubes."qixos-admin" = {
      #  properties = {
      #    label = "black";
      #    netvm = "sys-net";
      #  };

      #  remoteFlake = {
      #    url = "git+https://codeberg.org/originalposter/qixos-community?ref=master&dir=users/op/nubes/standalones/qixos-admin";
      #    output = "qixosStandaloneConfigurations.default";
      #  };
      #};

    };
  };
}
