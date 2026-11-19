{
  description = ''
    sys-mullvad: the netvm that sends other qubes through Mullvad. See
    modules/blueprints/mullvad-netvm.nix.
  '';

  inputs = {
    opQixCommunity = {
      url = "path:../../../";
    };

    qixCore = {
      url = "git+https://github.com/originalposter/qixos?ref=refs/tags/v0.2.0";
    };
  };

  outputs = { self, opQixCommunity, qixCore, ... }:
  {
    # In the outer config, `providesNetwork = true` and a netvm of its own, sys-firewall
    # or sys-net.
    qixosAppConfigurations.default = qixCore.lib.mkNubeApp {
      modules = [
        opQixCommunity.nixosModules.modules.blueprints.mullvad-netvm
        { services.mullvad-vpn.gui.enable = true; }

        opQixCommunity.nixosModules.modules.blueprints.basic-template
      ];
    };
  };
}
