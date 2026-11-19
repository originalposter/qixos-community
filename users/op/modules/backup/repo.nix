# The repo nube: holds the restic repositories of the nubes that back up (client.nix),
# and serves each of those nubes its own repository over the qrexec service
# qixos.ResticBackup.
#
# rclone copies files to and from many kinds of storage, a local directory, sftp, S3, B2
# and others, behind one interface. restic does all the chunking, deduplication and
# encryption itself, so the storage end only stores named files, and `rclone serve
# restic` answers restic's protocol and keeps those files wherever rclone points.
#
# The service runs it for one connection, on the repository at `<caller>` under
# `storage.path`, where the caller is the name qrexec gives it. A nube cannot set that
# name, and a qube name cannot contain a slash or start with a dot, so each nube reaches
# its own repository and nothing else. It is append-only: a compromised nube can add
# snapshots but not forget or prune them, so pruning happens here, by hand, with that
# nube's password.
#
# By default the storage is rclone's `local` type, a directory in this nube's private
# volume, so with no server at all the backups are still off the nubes they came from.
# Each repository there is a plain restic repository: copy it to a USB stick and
# `restic -r <copy>` reads it with no service involved. Other `storage.settings`, such as
# `{ type = "sftp"; host = ...; }`, pass the backups on to a server instead.
#
# The settings become rclone's RCLONE_CONFIG_STORAGE_* variables, so no rclone config
# file exists anywhere. They are in the nix store, which the cluster shares, so secrets,
# and a host you would rather not have there, go in `storage.environmentFile` in this
# nube instead. A server's credentials can do anything on it: append-only holds only on
# this side, so give them append-only rights on the server too where it has them.
#
# An sftp server's host key is trusted on first use. Unless the settings name a
# known_hosts_file, the service records the server's keys in ~/.config/qixos-backup/
# known_hosts on its first connection and checks every later one against them, so a
# server that changes its key fails every backup until that file is deleted. The first
# connection is trusted blindly; to pin a key instead, write the file yourself and set
# known_hosts_file to it. To close that gap after the fact, compare
# `ssh-keygen -lf ~/.config/qixos-backup/known_hosts` here with the server's
# `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` once, after the first backup.
#
# dom0 policy, in a file under /etc/qubes/policy.d/, for the nubes the admin manages:
#
#   qixos.ResticBackup * @tag:created-by-<admin> <this-nube> allow
#
# That admits templates and nubes without backups too. A tag of your own on the nubes
# that back up, in the source column, narrows it to them.
{ pkgs, lib, config, ... }:
let
  cfg = config.qixosBackupRepo;

  serviceName = "qixos.ResticBackup";

  variables = lib.concatStrings (lib.mapAttrsToList (name: value: ''
    export RCLONE_CONFIG_STORAGE_${lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] name)}=${lib.escapeShellArg value}
  '') cfg.storage.settings);

  knownHosts = "/home/${config.services.qubes.core.username}/.config/qixos-backup/known_hosts";

  service = pkgs.writeShellScript serviceName ''
    caller=''${QREXEC_REMOTE_DOMAIN:?qrexec names the caller}
    ${variables}
    ${lib.optionalString (cfg.storage.environmentFile != null) ''
      set -a
      . ${lib.escapeShellArg cfg.storage.environmentFile}
      set +a
    ''}
    if [ "''${RCLONE_CONFIG_STORAGE_TYPE:-}" = sftp ] && [ -z "''${RCLONE_CONFIG_STORAGE_KNOWN_HOSTS_FILE:-}" ]; then
      if [ ! -s ${knownHosts} ]; then
        ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname ${knownHosts})"
        # Every key type the server offers, so whichever rclone negotiates is known. A
        # temporary file moved into place, so two first calls cannot interleave.
        tmp=$(${pkgs.coreutils}/bin/mktemp ${knownHosts}.XXXXXX)
        ${pkgs.openssh}/bin/ssh-keyscan -p "''${RCLONE_CONFIG_STORAGE_PORT:-22}" \
          "''${RCLONE_CONFIG_STORAGE_HOST:?no storage host set}" > "$tmp" 2> /dev/null
        if [ ! -s "$tmp" ]; then
          ${pkgs.coreutils}/bin/rm -f "$tmp"
          echo "qixos.ResticBackup: could not read the host keys of $RCLONE_CONFIG_STORAGE_HOST" >&2
          exit 1
        fi
        ${pkgs.coreutils}/bin/mv -n "$tmp" ${knownHosts}
        ${pkgs.coreutils}/bin/rm -f "$tmp"
      fi
      export RCLONE_CONFIG_STORAGE_KNOWN_HOSTS_FILE=${knownHosts}
    fi
    exec ${pkgs.rclone}/bin/rclone serve restic -q --stdio --append-only "storage:${cfg.storage.path}/$caller"
  '';

  servicePackage = pkgs.runCommand serviceName { } ''
    mkdir -p $out/etc/qubes-rpc
    cp ${service} $out/etc/qubes-rpc/${serviceName}
  '';
in
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
        example = { type = "sftp"; host = "backup.example.org"; user = "qixos"; };
        description = "rclone's settings for where the repositories are stored, by rclone's names for them. The default is a directory in this nube. Nothing secret: they are in the nix store.";
      };

      path = lib.mkOption {
        type = lib.types.str;
        default = "/home/${config.services.qubes.core.username}/qixos-backup-repos";
        description = "Directory or bucket the repositories go in, on the storage.";
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/home/user/.config/qixos-backup-storage.env";
        description = "File in this nube of `RCLONE_CONFIG_STORAGE_<SETTING>=` lines, for settings kept out of the nix store: secrets, and a host you would rather not have there.";
      };
    };

    # For running the service directly, as the tests do.
    service = lib.mkOption {
      type = lib.types.path;
      internal = true;
      readOnly = true;
      default = service;
      description = "The qixos.ResticBackup service program.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.qubes.qrexec.packages = [ servicePackage ];
    environment.systemPackages = [ pkgs.rclone pkgs.restic ];
  };
}
