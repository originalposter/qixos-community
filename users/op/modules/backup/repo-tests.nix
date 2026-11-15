# Tests for repo.nix, which imports this file. Declared only when the repo service is
# enabled, and installed when qixosTests.enable is on.
#
# restic runs the service directly, with QREXEC_REMOTE_DOMAIN set the way qrexec would
# set it, so these cover everything but the qrexec hop. Callers are named test-repo-*,
# and their repositories are removed before and after, so the storage must be rclone's
# `local` type, a directory here.
{ pkgs, lib, config, ... }:
let
  cfg = config.qixosBackupRepo;

  repos = cfg.storage.path;

  mkTest = name: text: pkgs.writeShellApplication {
    inherit name text;
    runtimeInputs = with pkgs; [ coreutils jq restic ];
  };

  fixture = ''
    scratch=
    cleanup() { rm -rf "$scratch" ${repos}/test-repo-a ${repos}/test-repo-b; }
    cleanup
    trap cleanup EXIT
    scratch=$(mktemp -d)
    mkdir "$scratch/data"
    echo kept > "$scratch/data/file"

    # restic as one caller: its own program reaching the service as that caller.
    as() {
      local caller=$1
      shift
      printf '#!/bin/sh\nQREXEC_REMOTE_DOMAIN=%s exec %s\n' "$caller" ${cfg.service} > "$scratch/as-$caller"
      chmod +x "$scratch/as-$caller"
      RESTIC_PASSWORD=test-repo-password restic --no-cache -q -r rclone:qixos: \
        -o rclone.program="$scratch/as-$caller" "$@"
    }
  '';
in
{
  config = lib.mkIf cfg.enable {
    qixosTests.tests = {

      # The caller's name comes from qrexec, which a nube cannot forge, and is the only
      # thing choosing the repository. One nube must not reach another's.
      backup-repo-keeps-callers-apart = mkTest "backup-repo-keeps-callers-apart" ''
        ${fixture}
        as test-repo-a init
        as test-repo-a backup "$scratch/data"

        status=0
        as test-repo-b cat config > /dev/null 2>&1 || status=$?
        if [ "$status" -ne 10 ]; then
          echo "test-repo-b did not get an empty place of its own (restic exited $status)" >&2
          exit 1
        fi
        if [ "$(as test-repo-a snapshots --json | jq length)" != 1 ]; then
          echo "test-repo-a's snapshot is not where it backed up to" >&2
          exit 1
        fi
        echo "test-repo-b saw nothing of test-repo-a's repository"
      '';

      # A compromised nube can reach its own repository, so it must not be able to
      # destroy what is in it.
      backup-repo-is-append-only = mkTest "backup-repo-is-append-only" ''
        ${fixture}
        as test-repo-a init
        as test-repo-a backup "$scratch/data"
        id=$(as test-repo-a snapshots --json | jq -r '.[0].id')

        if as test-repo-a forget "$id" > /dev/null 2>&1; then
          echo "forgot a snapshot through the service" >&2
          exit 1
        fi
        if [ "$(as test-repo-a snapshots --json | jq length)" != 1 ]; then
          echo "the snapshot is gone" >&2
          exit 1
        fi
        echo "refused to forget, and the snapshot is still there"
      '';

      # Repositories land at the configured path, under the caller's name.
      backup-repo-uses-its-storage = mkTest "backup-repo-uses-its-storage" ''
        ${fixture}
        as test-repo-a init
        if [ ! -e ${repos}/test-repo-a/config ]; then
          echo "no repository at ${repos}/test-repo-a" >&2
          exit 1
        fi
        echo "the repository is at the storage's path and the caller's name"
      '';
    };
  };
}
