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
        not it -- leaving this unset inherits the widest window of all. For
        per-operation approval, reach for `pinentry` instead: it works one
        layer down, in gpg-agent, and is not subject to this window at all. 0 does
        not manage it either: qubes.Gpg stamps a file and compares
        whole-second mtimes, so it still silently auto-accepts anything
        arriving in the same second as the approval. -1 does prompt every
        time, but relies on undocumented arithmetic that would fail *open* if
        upstream ever validated this variable, and it renders the consent
        dialog as "for the following -1 seconds".
      '';
    };

    pinentry = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      example = lib.literalExpression "pkgs.pinentry-gnome3";
      description = ''
        Pinentry for gpg-agent in this qube, enabling passphrase-protected
        backend keys. `null` keeps the agent unconfigured, which in practice
        means the keys must be passphraseless.

        It must be a *graphical* pinentry. Nothing here has a controlling
        terminal, so pinentry-curses fails with "Inappropriate ioctl for
        device" -- the error usually misread as proof that passphrases cannot
        work under split GPG at all.

        They can. qrexec services run as the default user are forked from
        qrexec-fork-server, which qubes-gui-agent autostarts inside the
        graphical session, so DISPLAY is set -- the same reason upstream's
        zenity consent dialog works. gpg passes its own DISPLAY to the agent
        per connection, so the prompt lands in this qube even though the agent
        is socket-activated by systemd with no display of its own.
      '';
    };

    passphraseCacheSeconds = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 0;
      example = 600;
      description = ''
        How long gpg-agent caches the key passphrase. Only has an effect when
        `pinentry` is set.

        0, the default, prompts on every operation. That is the guarantee
        `autoAccept` cannot give: the qrexec consent dialog approves a *qube*
        for a window of time, while this approves each individual use of the
        key, the same shape as `ssh-add -c` in the split-SSH vault.
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
    #
    # Setting `pinentry` is the exception: the nixpkgs module below pulls its
    # own gnupg into systemPackages as a side effect. That is the copy you
    # manage the keyring with, and it is a different one from the pinned gnupg
    # the qrexec services carry -- they share only ~/.gnupg and the agent
    # socket, which is all they need to.
    programs.gnupg.agent = lib.mkIf (cfg.pinentry != null) {
      enable = true;
      pinentryPackage = cfg.pinentry;
      settings = {
        default-cache-ttl = cfg.passphraseCacheSeconds;
        max-cache-ttl = cfg.passphraseCacheSeconds;
      };
    };
  };
}
