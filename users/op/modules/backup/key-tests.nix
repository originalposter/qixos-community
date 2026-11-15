# Tests for key.nix, which imports this file. Declared only when the tool is enabled, and
# installed when qixosTests.enable is on.
#
# The passphrase goes in on stdin. The tool reads stdin rather than prompting when it is
# not a terminal, which is how these run over ssh and how a test can drive it at all.
{ pkgs, lib, config, ... }:
let
  cfg = config.qixosBackupKey;

  mkTest = name: text: pkgs.writeShellApplication {
    inherit name text;
    runtimeInputs = [ pkgs.coreutils pkgs.gnugrep ];
  };
in
{
  config = lib.mkIf cfg.enable {
    qixosTests.tests = {

      # The whole scheme rests on this: the same passphrase and name give the same
      # password on a new machine, and nothing else does. A name or a passphrase that
      # leaked into the other's output would show up as two outputs being equal.
      backup-key-derives-per-nube = mkTest "backup-key-derives-per-nube" ''
        derive() {
          printf '%s\n' "$1" | qixos-backup-key "$2" 2>/dev/null \
            || { echo "qixos-backup-key failed for $2" >&2; exit 1; }
        }
        a=$(derive "test master" test-a)
        again=$(derive "test master" test-a)
        b=$(derive "test master" test-b)
        other=$(derive "other master" test-a)

        if ! grep -qx 'RESTIC_PASSWORD=.\+' <<< "$a"; then
          echo "printed no password: $a" >&2
          exit 1
        fi
        if [ "$a" != "$again" ]; then
          echo "the same passphrase and name gave two different passwords" >&2
          exit 1
        fi
        if [ "$a" = "$b" ] || [ "$a" = "$other" ]; then
          echo "a different name or passphrase gave the same password" >&2
          exit 1
        fi
        echo "deterministic, and distinct per name and per passphrase"
      '';

      # Existing repositories are encrypted with what the tool printed when they were made,
      # so its output must never change; see the top of key.nix.
      backup-key-derivation-is-unchanged = mkTest "backup-key-derivation-is-unchanged" ''
        stderr=$(mktemp)
        trap 'rm -f "$stderr"' EXIT
        out=$(printf 'test master\n' | qixos-backup-key test-a 2> "$stderr") \
          || { echo "qixos-backup-key failed" >&2; exit 1; }
        if [ "$out" != RESTIC_PASSWORD=e968b4cc360aebd41dd2e7e33a1375d6fae2eff7a40e7bf8ed3ec898dff4ee99 ]; then
          echo "the password for test-a changed: $out" >&2
          exit 1
        fi
        if ! grep -qx 'passphrase fingerprint: 3f0eadad' "$stderr"; then
          echo "the fingerprint changed: $(cat "$stderr")" >&2
          exit 1
        fi
        echo "the same password and fingerprint as when the scheme was made"
      '';
    };
  };
}
