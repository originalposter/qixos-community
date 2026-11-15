{ pkgs, lib, config, ... }:
{
  imports = [
    ../../tests/runner.nix
    ./key-tests.nix
  ];

  options.qixosBackupKey.enable = lib.mkEnableOption "qixos-backup-key, which derives every nube's backup password from one passphrase";
}
