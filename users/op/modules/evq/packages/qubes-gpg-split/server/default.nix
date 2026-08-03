# The split-gpg backend: the qube that holds the private keys and serves
# signing/decryption to other qubes over qrexec. It should have no netvm --
# nothing here enforces that, it belongs in the outer config.
#
# dom0 must also be told to permit qubes.Gpg from each client qube; qixos-rebuild
# does not manage application policy. See this directory's README.
{ config, lib, pkgs, ... }:
let
  cfg = config.qubes.gpgSplitServer;
in
{
  options.qubes.gpgSplitServer = {
    enable = lib.mkEnableOption "qubes split-gpg backend (the key-holding qube)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../package { };
      defaultText = lib.literalExpression "pkgs.callPackage ../package { }";
      description = "The qubes-gpg-split package providing the backend services.";
    };

    autoAccept = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.unsigned;
      default = null;
      example = 300;
      description = ''
        How long, in seconds, this qube remembers a client's consent before
        prompting again.

        `null`, the default, leaves QUBES_GPG_AUTOACCEPT unset so that
        qubes.Gpg applies its own built-in default (300 as of 2.0.77). This
        defers to upstream deliberately: if they tighten that default, or add
        a way to approve exactly one request, we inherit it without changing
        anything here.

        Setting a value high enough to span a work session weakens the
        guarantee that each use of the key was individually approved.

        No setting cleanly gives "approve exactly one request", and `null` is
        not it -- leaving this unset inherits the widest window of all. 0 does
        not manage it either: qubes.Gpg stamps a file and compares
        whole-second mtimes, so it still silently auto-accepts anything
        arriving in the same second as the approval. -1 does prompt every
        time, but relies on undocumented arithmetic that would fail *open* if
        upstream ever validated this variable, and it renders the consent
        dialog as "for the following -1 seconds".
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # qubes.Gpg and qubes.GpgImportKey ship in the package's etc/qubes-rpc.
    # The core qrexec module puts them on QREXEC_SERVICE_PATH from here.
    services.qubes.qrexec.packages = [ cfg.package ];

    # Upstream's tmpfiles snippet, creating /run/qubes-gpg-split for the
    # per-client consent stamp files. The service runs as the primary user,
    # who is in the `qubes` group that owns the directory.
    systemd.tmpfiles.packages = [ cfg.package ];

    # qubes.Gpg reads this at request time to decide how long consent lasts.
    # qrexec-agent execs the service through a *login* shell, so /etc/profile
    # -- and therefore NixOS's /etc/set-environment -- is sourced and this is
    # visible to the service. Note it fails open: if it ever stops
    # propagating, the script falls back to its own built-in default.
    environment.variables = lib.mkIf (cfg.autoAccept != null) {
      QUBES_GPG_AUTOACCEPT = toString cfg.autoAccept;
    };

    # Deliberately no gnupg in systemPackages. The qrexec services resolve
    # against their own pinned gnupg, which also carries the gpg-agent they
    # exec, so nothing here needs it. Whether this qube also gets an
    # interactive gpg for managing the keyring is the config's call.
  };
}
