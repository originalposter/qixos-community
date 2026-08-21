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

          # Kept, like the smoke template and for the same reason: otherwise every run
          # pays for a fresh clone of the base template. Nothing else uses this one and
          # the cluster has no AppVMs to inherit its memory, so leaving it starved
          # affects nothing but the scenario that wants it that way. It also means
          # memory and maxmem set by hand survive, which is what lets this scenario work
          # before those properties are reconciled.
        };

        # The switch never gets far enough to build one, so an AppVM here would only be
        # another qube to create and tear down.
        appVms = { };
      };
    };
  };
}
