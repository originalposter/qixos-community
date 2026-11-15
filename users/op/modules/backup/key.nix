# qixos-backup-key: derives every nube's backup password from one passphrase. Belongs in
# the password nube and nowhere else, since whoever can run it with the passphrase can
# read every nube's backups.
#
#   qixos-backup-key <nube>   the env file for that nube, see client.nix
#
# Nothing is stored, here or anywhere. The passphrase goes through scrypt once into a
# root key, and each password is an HMAC of that root key over the nube's name. So a new
# machine needs the passphrase and the names and nothing else, and the names are in the
# repo nube: each nube's repository is named after it.
#
# One password per nube rather than one shared by all of them, so that a compromised
# nube holds the key to its own backups only. Derived rather than random, so that there
# is nothing per nube to back up or to type in on a new machine.
#
# The salt is fixed, which is what makes the derivation repeatable without anything
# stored. It is no weaker for that against the one attack a salt is for: there is
# exactly one passphrase, so there is nothing to precompute across. What it rests on is
# the passphrase being strong, since anyone holding one nube's ciphertext can test
# guesses against it at scrypt's cost.
#
# A short fingerprint of the root key goes to stderr on every run. Writing it down next
# to the passphrase catches a typo before it becomes a nube whose password no later run
# reproduces.
{ pkgs, lib, config, ... }:
let
  cfg = config.qixosBackupKey;

  tool = pkgs.writers.writePython3Bin "qixos-backup-key" {
    flakeIgnore = [ "E501" ];
  } ''
    import argparse
    import getpass
    import hashlib
    import hmac
    import sys

    # Changing any of these changes every password, so they are versioned rather than
    # tuned. n = 2**17 costs 128 MiB and about half a second.
    SALT = b"qixos-backup-key v1"
    SCRYPT = dict(n=2**17, r=8, p=1, maxmem=256 * 1024 * 1024, dklen=32)

    parser = argparse.ArgumentParser(description="Derive a nube's backup password.")
    parser.add_argument("nube")
    args = parser.parse_args()

    # A prompt when there is someone to answer it, stdin otherwise, so it can be piped.
    if sys.stdin.isatty():
        passphrase = getpass.getpass("Backup passphrase: ")
    else:
        passphrase = sys.stdin.readline().rstrip("\n")
    if not passphrase:
        sys.exit("empty passphrase")

    root = hashlib.scrypt(passphrase.encode(), salt=SALT, **SCRYPT)

    # Of the root key alone, so it is the same whichever nube it is run for.
    fingerprint = hmac.new(root, b"fingerprint", hashlib.sha256).hexdigest()[:8]
    print(f"passphrase fingerprint: {fingerprint}", file=sys.stderr)

    password = hmac.new(root, f"repository\0{args.nube}".encode(), hashlib.sha256).hexdigest()
    print(f"RESTIC_PASSWORD={password}")
  '';
in
{
  imports = [
    ../../tests/runner.nix
    ./key-tests.nix
  ];

  # Fixed, so that a nube importing this both by path (the password blueprint does) and
  # through the flake's export gets it once instead of declaring its option twice.
  key = "qixos-backup-key";

  options.qixosBackupKey.enable = lib.mkEnableOption "qixos-backup-key, which derives every nube's backup password from one passphrase";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ tool ];
  };
}
