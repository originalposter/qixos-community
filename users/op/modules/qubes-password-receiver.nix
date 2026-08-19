# Destination half of split password entry. Exposes a qrexec service that reads a
# credential off stdin and puts it in this qube's own clipboard, so the user pastes it
# with an ordinary Ctrl-V. Pair with qubes-password-menu.nix in the vault.
#
# The payload is one line for a password alone, or two lines for a username followed by
# a password. In the two line case the username goes to the clipboard first and the
# password replaces it once the username has actually been pasted, so a login form is
# two Ctrl-V presses with nothing to click in between.
#
# Security tradeoff: this qube ends up holding the plaintext of whatever was sent, and
# anything running in it can read the clipboard. That is the point of the feature and
# cannot be walked back, so send only credentials this qube is meant to use. The gate is
# the dom0 `ask` prompt on the vault's side; with an `allow` line instead, a subverted
# vault can push secrets in here silently.
{ pkgs, lib, config, ... }:
let
  cfg = config.qubesPasswordReceiver;

  clip = "xclip -selection ${cfg.selection}";

  # xsel for the clearing, xclip for everything else. Feeding xclip an empty selection
  # is not a reliable clear, since whether it takes ownership of zero bytes at all
  # varies, and a clear that quietly does nothing is the wrong thing to guess about.
  # xsel has an explicit --clear, and X puts no permission check on taking a selection
  # away from whichever client owns it.
  clearClip = "xsel --${cfg.selection} --clear";

  # A separate program, detached from the qrexec call, because handing over the
  # password means waiting for the user to paste and the call must not stay open that
  # long. It takes the payload on stdin; in argv a password would be in everyone's `ps`
  # output.
  deliver = pkgs.writeShellApplication {
    name = "qixos-password-deliver";
    runtimeInputs = with pkgs; [ coreutils gnused xclip xsel ];
    text = ''
      # A qrexec service inherits none of the user session's X variables, and the
      # qube's session is :0 (qixos core gui.nix).
      export DISPLAY="''${DISPLAY:-:0}"

      payload=$(cat)
      username=$(printf '%s\n' "$payload" | sed -n '1p')
      password=$(printf '%s\n' "$payload" | sed -n '2p')

      if [ -z "$password" ]; then
        password="$username"
        username=""
      fi

      if [ -n "$username" ]; then
        # -verbose is load bearing: xclip forks into the background when quiet, and
        # then exiting after -loops requests tells us nothing. In the foreground its
        # exit is the signal that the username has been served to a paste.
        #
        # A paste is not one request. Toolkits ask for TARGETS before asking for the
        # text, so waiting for a single request hands over the password before the
        # username is ever pasted. See pasteRequests if this hands over early or late.
        if ! printf '%s' "$username" |
          timeout ${toString cfg.pasteTimeoutSeconds} \
          ${clip} -verbose -in -loops ${toString cfg.pasteRequests} 2>/dev/null; then
          # Nobody pasted. Leaving the username sitting in the clipboard would be the
          # wrong half of the credential to abandon there.
          ${clearClip}
          echo "qixos-password-deliver: username was never pasted, nothing handed over" >&2
          exit 1
        fi
      fi

      printf '%s' "$password" | ${clip} -in
    '' + lib.optionalString (cfg.clearSeconds > 0) ''

      sleep ${toString cfg.clearSeconds}

      # Leave anything the user copied in the meantime alone.
      if [ "$(${clip} -out 2>/dev/null || true)" = "$password" ]; then
        ${clearClip}
      fi
    '';
  };

  pasteScript = pkgs.writeShellApplication {
    name = cfg.serviceName;
    runtimeInputs = with pkgs; [ coreutils util-linux ];
    text = ''
      payload=$(cat)

      if [ -z "$payload" ]; then
        echo "${cfg.serviceName}: empty payload, clipboard left alone" >&2
        exit 1
      fi

      # setsid and the redirections both matter: the qrexec call does not complete
      # while a child still holds its pipes, and the process group dies with the
      # service.
      printf '%s' "$payload" | setsid -f ${deliver}/bin/qixos-password-deliver >/dev/null 2>&1
    '';
  };

  pasteService = pkgs.runCommand cfg.serviceName {} ''
    mkdir -p $out/etc/qubes-rpc
    cp ${pasteScript}/bin/${cfg.serviceName} $out/etc/qubes-rpc/${cfg.serviceName}
  '';
in
{
  options.qubesPasswordReceiver = {
    enable = lib.mkEnableOption "receiving a credential from a vault qube into this qube's clipboard";

    serviceName = lib.mkOption {
      type = lib.types.str;
      default = "qixos.PasswordPaste";
      description = ''
        qrexec service to expose. Must match the vault's
        `qubesPasswordMenu.serviceName` and the dom0 policy lines.
      '';
    };

    selection = lib.mkOption {
      type = lib.types.enum [ "clipboard" "primary" "secondary" ];
      default = "clipboard";
      description = "X selection to deliver into. `clipboard` is the one Ctrl-V reads.";
    };

    clearSeconds = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 45;
      description = ''
        Seconds before the password is wiped from the selection again, counted from
        when it lands there rather than from when the payload arrived. 0 leaves it
        indefinitely, which means the next thing to read the clipboard gets it,
        including a web page that asks for it.
      '';
    };

    pasteRequests = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = ''
        How many X selection requests count as the username having been pasted, before
        the password takes its place.

        Not the same as one paste. An application typically asks for TARGETS and then
        for the text itself, which is why the default is 2 rather than 1. Some ask for
        more. If the password shows up while the username is still needed, raise this;
        if the username has to be pasted twice, lower it.
      '';
    };

    pasteTimeoutSeconds = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 60;
      description = ''
        How long to hold the username in the clipboard waiting for it to be pasted. On
        expiry the clipboard is cleared and the password is never handed over, on the
        assumption that the user walked away from a half filled login form. 0 waits
        forever.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Both, because the service uses both and someone debugging by hand in this qube
    # needs the same tools it does.
    environment.systemPackages = [ pkgs.xclip pkgs.xsel ];

    services.qubes.qrexec.packages = [ pasteService ];
  };
}
