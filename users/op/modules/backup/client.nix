# Backs up a nube's whole private volume, /rw, or the directories in `qixosBackup.paths`,
# to its restic repository in a repo nube (repo.nix). /rw is the only per-nube state that outlives a boot (everything else is the
# template's root, rebuilt from config), so with the config in git and /rw in a backup a
# nube can be recreated on other hardware. Caches are left out: ~/.cache, node_modules,
# and any directory marked with a CACHEDIR.TAG, which is how cargo's target/ is found.
#
# Getting there. The nube needs no netvm: restic's rclone backend runs a program and
# speaks its REST protocol over that program's stdin and stdout, and the program here is
# a qrexec call to qixos.ResticBackup in the repo nube. The repo nube picks the
# repository by this nube's qrexec name, so nothing here names it and no login is
# needed. The dom0 policy line is in repo.nix.
#
# The password. Only ever in /rw/qixos/backup/env, never in nix: a cluster shares its
# store, and every sibling can read every nube's config. The file is the line
# `qixos-backup-key <nube>` prints in the password nube (key.nix). From there:
#
#   qvm-copy                                                     # in the password nube
#   sudo install -D -m 600 ~/QubesIncoming/<vault>/env /rw/qixos/backup/env
#   sudo qixos-restore
#
# Restoring. Backups do not run until `qixos-restore` has, which a fresh nube has not.
# Its timer would otherwise fire before anyone restored it and make an empty /rw the
# latest snapshot, and restoring "latest" afterwards would bring back nothing. On a repo
# with nothing in it yet, qixos-restore restores nothing and only turns backups on, so
# a nube new to backups runs it too. The marker only exists while no restore is under
# way: it is kept out of the snapshots, so none brings it back halfway through, and a
# restore removes it before starting, so a second restore cannot leave the timer free
# to back up a half-restored /rw as the latest.
#
# The timer counts from boot, not by the calendar: an AppVM's root, where systemd keeps a
# timer's last run, is new every boot, so `Persistent` would never catch up a missed run.
# restic's cache is in /rw for the same reason, and its CACHEDIR.TAG keeps it out of the
# backup.
#
# A failing backup is a failed unit, not a skipped one, so a nube whose password was
# never put in place shows up in `systemctl --failed` instead of going quietly unbacked.
#
# `restic-nube` is restic with this nube's repository and password, for anything by
# hand: `sudo restic-nube snapshots`, `sudo restic-nube restore <id> --target /`.
{ pkgs, lib, config, ... }:
let
  cfg = config.qixosBackup;

  dir = "/rw/qixos/backup";
  marker = "${dir}/restored";

  # The wrapper the restic module generates, by the path it is always reachable at, since
  # sudo does not promise to keep the caller's PATH.
  resticNube = "/run/current-system/sw/bin/restic-nube";

  restore = pkgs.writeShellApplication {
    name = "qixos-restore";
    runtimeInputs = [ pkgs.coreutils pkgs.jq ];
    text = ''
      if [ "$(id -u)" != 0 ]; then
        echo "qixos-restore: run it as root, with sudo" >&2
        exit 1
      fi
      if [ ! -e ${dir}/env ]; then
        echo "qixos-restore: no ${dir}/env. Put in it the line RESTIC_PASSWORD=<password> that qixos-backup-key <this nube's name> prints, first." >&2
        exit 1
      fi

      # 10 is restic's code for a repository that does not exist yet, which the first
      # backup creates, so its complaint is held back. Any other failure, a wrong password
      # or an unreachable repo nube among them, must not be taken for an empty repo.
      status=0
      errors=$(mktemp)
      trap 'rm -f "$errors"' EXIT
      snapshots=$(${resticNube} snapshots --json 2> "$errors") || status=$?
      if [ "$status" -eq 10 ] || { [ "$status" -eq 0 ] && [ "$(jq length <<< "$snapshots")" -eq 0 ]; }; then
        touch ${marker}
        echo "Nothing to restore, the repository is empty. Backups are on."
        exit 0
      fi
      if [ "$status" -ne 0 ]; then
        cat "$errors" >&2
        echo "qixos-restore: could not read the repository, restic exited $status" >&2
        exit "$status"
      fi

      # Newest overall, not newest for this hostname. The repo nube picks the repository
      # by this nube's name, so to restore under a new name, rename the repository there
      # first.
      echo "Restoring ${lib.concatStringsSep " " cfg.paths} as of $(jq -r 'max_by(.time).time' <<< "$snapshots")."
      echo "Files there that are also in the snapshot will be replaced."
      read -r -p "Go on? [y/N] " answer || answer=
      if [ "$answer" != y ] && [ "$answer" != yes ]; then
        echo "Nothing restored. Type \"yes\" to restore." >&2
        exit 1
      fi

      rm -f ${marker}
      ${resticNube} restore latest --target /
      touch ${marker}
      echo "Restored. Reboot this nube so that what is running picks up the restored state."
    '';
  };
in
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

    # restic appends rclone's arguments and a remote name, which this ignores: the repo
    # nube decides what to serve.
    connect = lib.mkOption {
      type = lib.types.path;
      internal = true;
      default = pkgs.writeShellScript "qixos-backup-connect" ''
        exec ${pkgs.qubes-core-qrexec}/bin/qrexec-client-vm ${cfg.repoNube} qixos.ResticBackup
      '';
      description = "Program restic runs to reach the repo nube's service.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Named `nube` so the wrapper the restic module puts on PATH is `restic-nube`.
    services.restic.backups.nube = {
      # A placeholder: restic needs a remote name here and passes it to the connect
      # program, which ignores it. The repo nube chooses the repository, from this nube's
      # qrexec name.
      repository = "rclone:qixos:";
      extraOptions = [ "rclone.program=${cfg.connect}" ];
      environmentFile = "${dir}/env";
      inherit (cfg) paths;
      exclude = [ marker "/rw/home/*/.cache" "node_modules" ] ++ cfg.exclude;
      extraBackupArgs = [ "--exclude-caches" ];
      initialize = true;
      backupPrepareCommand = ''
        if [ ! -e ${marker} ]; then
          echo "not backing up: run qixos-restore first, so a fresh nube does not become the latest snapshot" >&2
          exit 1
        fi
      '';
      timerConfig = {
        OnBootSec = "10min";
        OnUnitActiveSec = "6h";
      };
    };

    systemd.services.restic-backups-nube = {
      # The wrapper reads this environment as well, so `restic-nube` shares the cache.
      environment.RESTIC_CACHE_DIR = lib.mkForce "${dir}/cache";

      # Only qrexec is involved, and a nube with no netvm may never reach
      # network-online, which would hold every backup until the wait times out.
      wants = lib.mkForce [ ];
      after = lib.mkForce [ ];
    };

    environment.systemPackages = [ restore ];
  };
}
