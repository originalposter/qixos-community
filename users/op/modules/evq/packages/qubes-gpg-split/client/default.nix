{ config, lib, pkgs, ... }:
{
  options.qubes.gpgSplitClient = {
    enable = lib.mkEnableOption "qubes split-gpg client";
    
    vaultName = lib.mkOption {
      type = lib.types.str;
      description = "Name of the vault qube holding your GPG keys";
    };

    aliasGpg = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Alias gpg to qubes-gpg-client-wrapper";
    };
  };

  config = lib.mkIf config.qubes.gpgSplitClient.enable {
    nixpkgs.overlays = [
      (final: prev: {
        qubes-gpg-split = final.callPackage ../package { };
      })
    ];

    environment.systemPackages = [ pkgs.qubes-gpg-split ];
    
    environment.sessionVariables.QUBES_GPG_DOMAIN = 
      config.qubes.gpgSplitClient.vaultName;

    environment.shellAliases = lib.mkIf config.qubes.gpgSplitClient.aliasGpg {
      gpg = "qubes-gpg-client-wrapper";
    };
  };
}
