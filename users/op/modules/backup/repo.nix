{ pkgs, lib, config, ... }:
{
  imports = [
    ../../tests/runner.nix
    ./repo-tests.nix
  ];

  options.qixosBackupRepo = {
    enable = lib.mkEnableOption "holding other nubes' restic repositories, served over qixos.ResticBackup";

    storage = {
      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { type = "local"; };
        description = "rclone's settings for where the repositories are stored.";
      };

      path = lib.mkOption {
        type = lib.types.str;
        default = "/home/${config.services.qubes.core.username}/qixos-backup-repos";
        description = "Directory or bucket the repositories go in, on the storage.";
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "File of RCLONE_CONFIG_STORAGE_<SETTING>= lines kept out of the nix store.";
      };
    };

    service = lib.mkOption {
      type = lib.types.path;
      internal = true;
      readOnly = true;
      default = pkgs.writeShellScript "qixos.ResticBackup" "exit 1";
      description = "The qixos.ResticBackup service program.";
    };
  };
}
