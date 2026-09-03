{
  description = ''
    Outer config for the OOM scenario: one template given too little memory to evaluate
    its own configuration, so the nix build inside qixos.Switch is killed part way.

    Its own scenario rather than a variant of smoke, because applying this is meant to
    fail and would take the other scenario's nubes down with it.

    The two values below want tuning against a real run. Too much and the build
    finishes; too little and the qube never boots, so qrexec refuses and the switch
    fails without an error code. The test reports those two cases differently from each
    other and from a pass, so a wrong value says which way it is wrong.
    '';

  inputs = {
  };

  outputs = { ... }:
  let
    prefix = "test-oom-";
    adminName = "qixos-admin-test";
  in {
    qixosConfigurations.oom = {
      managementTag = "created-by-${adminName}";
      baseTemplate = "${adminName}-base-template";

      nubeClusters."${prefix}template" = {
        template = {
          properties = {
            label = "red";

            # Two-sided: enough for the qube to boot and answer qrexec, not enough to
            # evaluate a nixos configuration, so the build is killed part way.
            memory = 200;

            # Without this qmemman balloons the qube up to maxmem on demand and the
            # build finishes, since `memory` is only the starting allocation. Zero
            # turns memory balancing off, pinning it at the value above.
            maxmem = 0;
          };

          localFlake = {
            path = "./users/op/tests/nubes/smoke";
            output = "qixosTemplateConfigurations.smoke";
          };
        };

        # Create a appVM to cause memory to increase
        appVms."${prefix}appvm" = {
          properties = {
            label = "red";
            netvm = "none";
            templateForDispvms = true;
          };

          localFlake = {
            path = "./users/op/tests/nubes/smoke";
            output = "qixosAppConfigurations.smoke";
          };
          deleteOnRemoval = true;
        };
      };
    };
  };
}
