# Tests for client.nix, which imports this file. Declared only when backups are enabled,
# and installed when qixosTests.enable is on.
#
# These run in a nube that is its own repo nube (the smoke flake's `backup` nube), with
# restic reaching the repo service directly rather than over qrexec. They wipe that
# nube's repository, at the smoke flake's storage path, and /rw/qixos/backup, so they
# belong only in a nube that exists to be tested.
{ pkgs, lib, config, ... }:
let
  cfg = config.qixosBackup;

  mkTest = name: text: pkgs.writeShellApplication {
    inherit name text;
    runtimeInputs = with pkgs; [ coreutils gnugrep jq ];
  };

  # A fixed password rather than one from qixos-backup-key, so these tests say nothing
  # about the key tool.
  fixture = ''
    # Also run first, for whatever an interrupted run left behind.
    cleanup() { sudo rm -rf /home/user/qixos-backup-test-repos/test-smoke-backup /rw/qixos/backup; }
    cleanup
    trap cleanup EXIT

    # What a person pastes in from qixos-backup-key, and nothing else: no marker, so the
    # nube looks freshly created.
    printf 'RESTIC_PASSWORD=test-repo-password\n' | sudo install -D -m 600 /dev/stdin /rw/qixos/backup/env

    backup() { sudo systemctl start restic-backups-nube; }
    restore() { echo y | sudo qixos-restore; }
    snapshots() { sudo restic-nube snapshots --json | jq length; }
  '';
in
{
  config = lib.mkIf cfg.enable {
    qixosTests.tests = {

      # A fresh nube's timer can fire before anyone restored it, and would make an empty
      # /rw the latest snapshot. See client.nix's header.
      backup-waits-for-restore = mkTest "backup-waits-for-restore" ''
        ${fixture}
        if backup; then
          echo "backed up a nube that qixos-restore had not run in" >&2
          exit 1
        fi
        if ! restore; then
          echo "qixos-restore failed on a repo that does not exist yet" >&2
          exit 1
        fi
        if ! backup; then
          echo "did not back up after qixos-restore" >&2
          exit 1
        fi
        if [ "$(snapshots)" != 1 ]; then
          echo "expected one snapshot, found $(snapshots)" >&2
          exit 1
        fi
        echo "refused before qixos-restore, backed up after it"
      '';

      # The thing the module is for. A file is backed up, the nube's state is removed the
      # way a new machine would lack it, and qixos-restore brings back the file with its
      # owner and mode, and leaves the marker that lets backups carry on.
      backup-restores-what-it-backed-up = mkTest "backup-restores-what-it-backed-up" ''
        ${fixture}
        restore
        dir=/home/user/qixos-backup-test
        rm -rf "$dir"
        mkdir "$dir"
        trap 'cleanup; rm -rf "$dir"' EXIT
        content=$(head -c 32 /dev/urandom | base64)
        echo "$content" > "$dir/sentinel"
        chmod 640 "$dir/sentinel"

        if ! backup; then
          echo "the backup failed" >&2
          exit 1
        fi

        rm -rf "$dir"
        sudo rm /rw/qixos/backup/restored
        if ! restore; then
          echo "qixos-restore failed" >&2
          exit 1
        fi

        if [ "$(cat "$dir/sentinel" 2> /dev/null)" != "$content" ]; then
          echo "the sentinel did not come back" >&2
          exit 1
        fi
        if [ "$(stat -c '%U %a' "$dir/sentinel")" != "user 640" ]; then
          echo "came back as $(stat -c '%U %a' "$dir/sentinel"), not user 640" >&2
          exit 1
        fi
        if ! sudo test -e /rw/qixos/backup/restored; then
          echo "no marker after the restore, so backups would stay off" >&2
          exit 1
        fi
        echo "the sentinel came back with its owner and mode"
      '';

      # A directory with a CACHEDIR.TAG stands for cargo's target/.
      backup-skips-caches = mkTest "backup-skips-caches" ''
        ${fixture}
        restore
        dir=/home/user/qixos-backup-test
        rm -rf "$dir" /home/user/.cache/qixos-backup-test
        trap 'cleanup; rm -rf "$dir" /home/user/.cache/qixos-backup-test' EXIT
        mkdir -p "$dir/target" "$dir/node_modules" /home/user/.cache/qixos-backup-test
        echo "Signature: 8a477f597d28d172789f06886806bc55" > "$dir/target/CACHEDIR.TAG"
        touch "$dir/kept" "$dir/target/built" "$dir/node_modules/dep" /home/user/.cache/qixos-backup-test/cached

        if ! backup; then
          echo "the backup failed" >&2
          exit 1
        fi
        listed=$(sudo restic-nube ls latest)
        if ! grep -qx /rw/home/user/qixos-backup-test/kept <<< "$listed"; then
          echo "an ordinary file was not backed up" >&2
          exit 1
        fi
        for skipped in qixos-backup-test/target/built qixos-backup-test/node_modules/dep .cache/qixos-backup-test/cached; do
          if grep -qx "/rw/home/user/$skipped" <<< "$listed"; then
            echo "backed up $skipped" >&2
            exit 1
          fi
        done
        echo "skipped ~/.cache, node_modules and a CACHEDIR.TAG directory"
      '';
    };
  };
}
