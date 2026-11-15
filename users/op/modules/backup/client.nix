{ pkgs, lib, config, ... }:
{
  imports = [
    ../../tests/runner.nix
    ./client-tests.nix
  ];

  options.qixosBackup = {
    enable = lib.mkEnableOption "backing up this nube's private volume to its repository in a repo nube";

    repoNube = lib.mkOption {
      type = lib.types.str;
      description = "Nube running backup.repo, the qixos.ResticBackup service, which keeps this nube's repository or passes it on to a remote.";
    };

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/rw" ];
      description = "Directories to back up. Only what is under /rw outlives a reboot.";
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "restic exclude patterns on top of the defaults.";
    };

    connect = lib.mkOption {
      type = lib.types.path;
      internal = true;
      description = "Program restic runs to reach the repo nube's service.";
    };
  };
}
