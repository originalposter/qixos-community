{
  description = ''
    Test nube cluster
  '';

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    opQixCommunity = {
      url = "path:../../../";
    };

    qixCore = {
      url = "git+https://github.com/originalposter/qixos?ref=remove-hm-privilege";
    };
  };

  outputs = { self, nixpkgs, home-manager, opQixCommunity, qixCore, ... }:
  let
    sharedModules = [
      opQixCommunity.nixosModules.modules.blueprints.basic-template
    ];
  in
  {
    qixosTemplateConfigurations.test = qixCore.lib.mkNubeTemplate { inherit nixpkgs home-manager; } {
      modules = [({ pkgs , ... }:{
        environment.systemPackages = with pkgs; [
          alacritty
        ];

        boot.plymouth.enable = false;

        boot.kernelParams = [
          "console=tty0"
          "console=hvc0"
          "systemd.log_level=info"
          "systemd.show_status=true"
        ];
      })] ++ sharedModules;

    };

    qixosAppConfigurations.test = qixCore.lib.mkNubeApp {
      # Make a direct switch possible
      directBuild = {
        inherit nixpkgs home-manager;
      };

      homeConfiguration = {
        modules = [ ({ pkgs, ... }:{
          home.packages = with pkgs; [ brave ];
            programs.firefox.enable = true;
        }) ];
      };
      # Here you can place root configurations for this AppVM
      rootConfiguration = {
        modules = [
          opQixCommunity.nixosModules.modules.qubes-split-ssh-client
          { qubesSplitSsh = { enable = true; vaultName = "split-ssh-nube"; }; }
          ({ pkgs, ... }: {
            environment.systemPackages = with pkgs; [
              signal-desktop
            ];

            systemd.user.services.qixos-user-test = {
              description = "qixos user systemd test marker";
              wantedBy = [ "default.target" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = pkgs.writeShellScript "qixos-user-test" ''
                  echo "started at $(date)" > /tmp/qixos-user-test.marker
                '';
              };
            };
          })
        ] ++ sharedModules;
      };
    };

    nixosConfigurations.template = self.qixosTemplateConfigurations.test.nixosConfigurations.default;
    nixosConfigurations.test = self.qixosAppConfigurations.test.nixosConfigurations.default;
    homeConfigurations.test = self.qixosAppConfigurations.test.homeConfigurations.default;
  };
}
