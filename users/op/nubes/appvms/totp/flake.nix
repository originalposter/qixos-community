{
  description = ''
    TOTP-nube
    Time-based One Time Password

    Nube configuration that sets up a TOTP authenticator based on pass
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
    qixosAppConfigurations.default = qixCore.lib.mkNubeApp {
      modules = [
        # Holds the TOTP seeds, so it must stay netvm = "none" in the outer config. It
        # also has to be a different qube from the password nube: a seed stored beside
        # the password it guards stops being a second factor.
        ({ pkgs, ... }: {
          environment.systemPackages = with pkgs; [
            # Seeds live in a pass store, which is the same idiom and the same backup
            # path as the password nube. `pass otp <entry>` prints a code and
            # `pass otp insert` takes an otpauth:// URI.
            (pass.withExtensions (exts: [ exts.pass-otp ]))

            # For managing this qube's own keyring by hand, which `pass init` needs
            # before there is a store at all.
            gnupg

            # Enrolment is nearly always a QR code and this qube has no camera.
            # `zbarimg shot.png` reads the otpauth:// URI out of an image copied in,
            # which can then go straight to `pass otp insert`.
            zbar

            # For a seed handed over as bare base32 with no URI around it:
            # `oathtool --totp -b <secret>`.
            oath-toolkit
          ];

          programs.gnupg.agent = {
            enable = true;
            # Graphical rather than curses, for the same reason as the password nube:
            # there is no tty for a curses pinentry to draw in when this is driven from
            # a keybind or a bare session, and `pass otp` would fail with no visible
            # prompt.
            pinentryPackage = pkgs.pinentry-qt;
          };
        })

        opQixCommunity.nixosModules.modules.blueprints.basic-template
      ];
    };
  };
}
