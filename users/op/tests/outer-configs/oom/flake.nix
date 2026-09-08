{
  description = ''
    Outer config for the OOM scenario: one template given too little memory to evaluate
    its own configuration, so the nix build inside qixos.Switch is killed part way.

    Its own scenario rather than a variant of smoke, because applying this is meant to
    fail and would take the other scenario's nubes down with it.

    The kill comes from one deliberately expensive nube rather than from starving the
    template outright. Starving it alone did not work: at memory=600 a switch thrashed
    against swap for over ten minutes without ever being killed. Demanding more than
    memory plus swap can hold gets there in one allocation instead.

    The template's memory and the nube's ENTRIES want tuning against a real run. Too
    much memory and the build finishes; too little and the qube never boots, so qrexec
    refuses and the switch fails without an error code. The test reports those two cases
    differently from each other and from a pass, so a wrong value says which way it is
    wrong.
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

            # Enough to boot and answer qrexec, which starving it below this does not
            # reliably do. What kills the build is the nube below, not this number.
            memory = 600;

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

        # The provocation. Its configuration is expensive to evaluate and cheap to
        # build, so the template runs out of memory part way through evaluating it.
        appVms."${prefix}appvm" = {
          properties = {
            label = "red";
            netvm = "none";
          };

          localFlake = {
            path = "./users/op/tests/nubes/smoke";
            output = "qixosAppConfigurations.oomHeavy";
          };
          deleteOnRemoval = true;
        };
      };
    };
  };
}
