{
  description = ''
    pgp-nube
  '';

  inputs = {
    opQixCommunity = {
      url = "path:../../../";
    };

    qixCore = {
      url = "git+https://codeberg.org/originalposter/qixos?ref=master";
    };
  };

  outputs = { self, opQixCommunity, qixCore, ... }:
  let
    # This qube is the split-gpg *backend*: it holds the private keys and
    # serves crypto over qrexec. It must stay netvm = "none" in the outer
    # config. The matching client module belongs in the qubes that consume it.
    splitGpgServer = opQixCommunity.nixosModules.modules.evq.packages.qubes-gpg-split.server;
  in
  {
    qixosAppConfigurations.pgp-nube = qixCore.lib.mkNubeApp {
      rootConfiguration = {
        modules = [
          splitGpgServer
          {
            qubes.gpgSplitServer.enable = true;
          }

          ({pkgs, ...}: {
            # gnupg is for managing the keyring by hand in this qube. The
            # split-gpg services do not use it -- they carry their own.
            environment.systemPackages = with pkgs; [ gnupg sequoia-sq ];
          })
        ] ++ [ opQixCommunity.nixosModules.modules.blueprints.basic-template ];
      };
    };
  };
}
