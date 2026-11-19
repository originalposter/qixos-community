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

    backup() { sudo qixos-backup-restic; }
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

      # A file that changed since the backup is the user's newer work, so a restore keeps
      # it unless told otherwise, and names it either way.
      backup-restore-keeps-changed-files = mkTest "backup-restore-keeps-changed-files" ''
        ${fixture}
        restore
        dir=/home/user/qixos-backup-test
        rm -rf "$dir"
        mkdir "$dir"
        trap 'cleanup; rm -rf "$dir"' EXIT
        echo old > "$dir/changed"
        backup
        echo new > "$dir/changed"

        out=$(restore 2>&1)
        if [ "$(cat "$dir/changed")" != new ]; then
          echo "the restore replaced a file that had changed since the backup" >&2
          exit 1
        fi
        if ! grep -q "$dir/changed" <<< "$out"; then
          echo "the restore did not name the file it kept:" >&2
          echo "$out" >&2
          exit 1
        fi
        echo "kept the changed file and named it"
      '';

      backup-restore-overwrite-replaces-changed-files = mkTest "backup-restore-overwrite-replaces-changed-files" ''
        ${fixture}
        restore
        dir=/home/user/qixos-backup-test
        rm -rf "$dir"
        mkdir "$dir"
        trap 'cleanup; rm -rf "$dir"' EXIT
        echo old > "$dir/changed"
        backup
        echo new > "$dir/changed"

        out=$(echo y | sudo qixos-restore --overwrite 2>&1)
        if [ "$(cat "$dir/changed")" != old ]; then
          echo "--overwrite did not replace the changed file" >&2
          exit 1
        fi
        if ! grep -q "$dir/changed" <<< "$out"; then
          echo "the restore did not name the file it replaced:" >&2
          echo "$out" >&2
          exit 1
        fi
        echo "replaced the changed file and named it"
      '';

      # --new turns backups on for a nube whose repository is empty, without backing up
      # immediately, and refuses one that has snapshots, which want restoring first.
      backup-new-starts-backups-on-an-empty-repo = mkTest "backup-new-starts-backups-on-an-empty-repo" ''
        ${fixture}
        if ! echo y | sudo qixos-restore --new; then
          echo "qixos-restore --new failed on an empty repository" >&2
          exit 1
        fi
        if ! sudo test -e /rw/qixos/backup/restored; then
          echo "--new did not turn backups on" >&2
          exit 1
        fi
        # 10 is restic's code for no repository: nothing has been backed up yet.
        status=0
        sudo restic-nube cat config > /dev/null 2>&1 || status=$?
        if [ "$status" -ne 10 ]; then
          echo "--new backed up instead of only turning backups on (restic-nube exited $status)" >&2
          exit 1
        fi
        echo "turned backups on, and backed nothing up"
      '';

      backup-new-refuses-a-repo-with-snapshots = mkTest "backup-new-refuses-a-repo-with-snapshots" ''
        ${fixture}
        restore
        backup
        sudo rm /rw/qixos/backup/restored

        # Answering the prompt, so a script that ignores --new and restores is caught.
        if echo y | sudo qixos-restore --new; then
          echo "qixos-restore --new went ahead on a repository that has snapshots" >&2
          exit 1
        fi
        if sudo test -e /rw/qixos/backup/restored; then
          echo "--new turned backups on although it refused" >&2
          exit 1
        fi
        if [ "$(snapshots)" != 1 ]; then
          echo "--new changed the repository: $(snapshots) snapshots" >&2
          exit 1
        fi
        echo "refused, and left backups off"
      '';

      # Nothing backs up on its own unless the nube asks for it.
      backup-is-manual-by-default = mkTest "backup-is-manual-by-default" ''
        if systemctl cat restic-backups-nube.timer > /dev/null 2>&1; then
          echo "a backup timer exists although qixosBackup.automatic is off" >&2
          exit 1
        fi
        echo "no backup timer"
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
