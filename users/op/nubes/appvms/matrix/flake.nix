{
  description = ''
    matrix nube
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
        ({ pkgs, ... }: {
          environment.systemPackages = with pkgs; [ xdg-utils element-desktop iamb brave ];
          xdg.mime.defaultApplications = {
            "text/html" = "brave-browser.desktop";
            "x-scheme-handler/http" = "brave-browser.desktop";
            "x-scheme-handler/https" = "brave-browser.desktop";
            "x-scheme-handler/io.element.desktop" = "element-desktop.desktop";
          };
        })

        opQixCommunity.nixosModules.modules.qix-pw.receiver
        { qixPwReceiver.enable = true; }

        opQixCommunity.nixosModules.modules.blueprints.basic-template
      ];
    };

    nixosConfigurations.default = self.qixosAppConfigurations.default.nixosConfigurations.default;
  };
}
