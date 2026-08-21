# Vault half of split password entry. Shows a rofi menu of `pass` entry names inside the
# qube holding the password store, and sends the chosen secret over qrexec to a qube
# dom0 picks. Pair with receiver.nix on the destination.
#
# With `--with-username` it also sends the account name, taken from the entry name
# rather than the entry body: an entry called `web/github.com+op@example.org` yields the
# username `op@example.org`. Reading it off the name means an entry never has to be
# decrypted just to find out what it is, so the menu stays a listing of file names.
# Entries not in that form are a hard error under the flag, not a silent fallback to
# password-only, because the caller asked for a username and would otherwise paste a
# password into a username field.
#
# The store, the gpg key and the list of entry names never leave this qube. One secret
# crosses the boundary per invocation, and dom0 decides where it lands.
#
# dom0 policy, in a file under /etc/qubes/policy.d/:
#
#   qixos.PasswordPaste * <vault> @tag:created-by-<admin> ask default_target=<qube>
#
# A tag in the destination column keeps the prompt's choices to qubes that admin manages.
#
# The call names this very qube as its target, which reads like a mistake and is not. A
# request has to name a qube that exists and that the destination column admits, or the
# policy does not resolve; our own name satisfies both without this program knowing any
# other qube's. Where the secret goes is wherever dom0 redirects the call to.
#
# It also fails closed. A qube cannot qrexec to itself, so a policy that stops
# redirecting, say `ask` relaxed to a plain `allow`, kills the call rather than
# delivering somewhere unintended.
{ pkgs, lib, config, ... }:
let
  cfg = config.qubesPasswordMenu;

  passwordMenu = pkgs.writeShellApplication {
    name = "qixos-password-menu";
    runtimeInputs = with pkgs; [
      coreutils findutils gnused rofi pass gnupg
      qubes-core-qrexec qubes-core-qubesdb
    ];
    text = ''
      # Quoted heredoc so the shell leaves $PASSWORD_STORE_DIR alone; nix has already
      # substituted the separator by the time bash reads this.
      usage() {
        cat <<'EOF'
usage: qixos-password-menu [-u|--with-username] [rofi options...]

Pick an entry from this qube's pass store and send its password to a qube dom0
chooses. Options this does not recognise are passed on to rofi.

  -u, --with-username  Send the account name before the password, taken from the
                       entry name rather than its contents. An entry called
                       web/github.com${cfg.usernameSeparator}op@example.org sends op@example.org,
                       then the password once the username has been pasted. An
                       entry with no ${cfg.usernameSeparator} is refused rather than sent without one.
  -h, --help           Show this.

Entries come from $PASSWORD_STORE_DIR, or ~/.password-store.
EOF
      }

      with_username=0
      # Unrecognised arguments go to rofi, which is how the caller sets a font or
      # colours from the keybind without this script knowing rofi's flags.
      rofi_args=()
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -u|--with-username) with_username=1; shift ;;
          -h|--help) usage; exit 0 ;;
          --) shift; rofi_args+=("$@"); break ;;
          *) rofi_args+=("$1"); shift ;;
        esac
      done

      store="''${PASSWORD_STORE_DIR:-$HOME/.password-store}"

      if [ ! -d "$store" ]; then
        echo "qixos-password-menu: no password store at $store" >&2
        exit 1
      fi

      # `pass ls` renders a tree for humans, so the entry paths would have to be
      # rebuilt from its indentation. Walking the store is what upstream passmenu does
      # for the same reason.
      entries=$(find "$store" -type f -name '*.gpg' -printf '%P\n' | sed 's/\.gpg$//' | sort)

      if [ -z "$entries" ]; then
        echo "qixos-password-menu: no entries in $store" >&2
        exit 1
      fi

      # Dismissing rofi exits non-zero, which under `set -e` would abort here instead
      # of being the no-op the user asked for.
      #
      # -normal-window so the menu is a managed window rather than override-redirect,
      # which is what lets the qubes window manager frame and label it as belonging to
      # this qube. A borderless menu over another qube's screen has nothing to say
      # whose it is.
      if ! entry=$(printf '%s\n' "$entries" |
        rofi -dmenu -normal-window -i -p '${cfg.prompt}' "''${rofi_args[@]}"); then
        exit 0
      fi

      [ -n "$entry" ] || exit 0

      username=""
      if [ "$with_username" -eq 1 ]; then
        # Last separator wins, so a service name may contain one.
        username="''${entry##*${cfg.usernameSeparator}}"
        if [ "$username" = "$entry" ] || [ -z "$username" ]; then
          echo "qixos-password-menu: $entry is not of the form <service>${cfg.usernameSeparator}<username>" >&2
          exit 1
        fi
      fi

      # sed rather than `head -n1`: head closes the pipe on the first line, and the
      # SIGPIPE that lands on gpg becomes a script failure through pipefail.
      secret=$(pass show "$entry" | sed -n '1p')

      if [ -z "$secret" ]; then
        echo "qixos-password-menu: $entry has an empty first line" >&2
        exit 1
      fi

      # Wire format: one line is the password alone, two lines are username then
      # password. Neither field can contain a newline, the password being the entry's
      # first line and the username a piece of a file name.
      #
      # The call blocks for as long as the dom0 prompt goes unanswered, so without a
      # timeout an ignored prompt leaves the secret sitting in a pipe indefinitely.
      # Giving up here does not take the prompt off dom0's screen; answering it later
      # just finds nobody on this end.
      self=$(qubesdb-read /name)

      status=0
      if [ -n "$username" ]; then
        printf '%s\n%s' "$username" "$secret" |
          timeout ${toString cfg.sendTimeoutSeconds} qrexec-client-vm "$self" ${cfg.serviceName} || status=$?
      else
        printf '%s' "$secret" |
          timeout ${toString cfg.sendTimeoutSeconds} qrexec-client-vm "$self" ${cfg.serviceName} || status=$?
      fi

      if [ "$status" -eq 124 ]; then
        echo "qixos-password-menu: timed out waiting for the dom0 prompt, nothing delivered" >&2
        exit 1
      elif [ "$status" -ne 0 ]; then
        echo "qixos-password-menu: qrexec call failed with status $status, denied by policy?" >&2
        exit "$status"
      fi
    '';
  };
in
{
  options.qubesPasswordMenu = {
    enable = lib.mkEnableOption "sending a password from this qube's store to another qube";

    serviceName = lib.mkOption {
      type = lib.types.str;
      default = "qixos.PasswordPaste";
      description = ''
        qrexec service to call on the destination. Must match the destination's
        `qubesPasswordReceiver.serviceName` and the dom0 policy lines.
      '';
    };

    prompt = lib.mkOption {
      type = lib.types.str;
      default = "pass:";
      description = "rofi prompt. Worth changing only to tell two stores apart.";
    };

    sendTimeoutSeconds = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 60;
      description = ''
        How long to wait for the qrexec call to go through, which in practice means how
        long the dom0 prompt may go unanswered before the send is abandoned. 0 waits
        forever.
      '';
    };

    usernameSeparator = lib.mkOption {
      type = lib.types.str;
      default = "+";
      description = ''
        What divides the service from the username in an entry name, for
        `--with-username`. Anything after the last one is the username.

        Not `/`, which pass already uses for directories, and not a character common in
        domain names, or every entry would look like it carried a username.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ passwordMenu ];
  };
}
