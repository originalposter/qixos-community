# Destination half of split password entry. Exposes a qrexec service that reads a
# credential off stdin and puts it in this qube's own clipboard, so the user pastes it
# with an ordinary Ctrl-V. Pair with menu.nix in the vault.
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

  # Owning the selection ourselves, rather than driving xclip, because a paste has to
  # be told apart from a negotiation and xclip cannot do it: `-loops` counts every
  # selection request, and `-verbose` reports only ordinals. Firefox asks for the text
  # alone, chromium asks what is on offer first and then for the text, so any fixed
  # count is right for one of them and wrong for the other. Too high and the username
  # has to be pasted twice; too low and the password lands in the username field.
  #
  # A request for a content target is one paste in both, which is the signal this waits
  # for.
  deliver = pkgs.writers.writePython3Bin "qixos-password-deliver" {
    libraries = [ pkgs.python3Packages.xlib ];
    flakeIgnore = [
      # nixpkgs passes --ignore, which replaces flake8's own default ignore list
      # rather than adding to it, so naming one code silently switches several
      # others back on. W503 and W504 contradict each other and are both in that
      # default list; leaving them on fails the build on a line break that the
      # opposite rule would require.
      "E501" "W503" "W504"
    ];
  } ''
    """Hold a credential in an X selection, handing the password over once pasted.

    Exiting drops the selection, which is what clearing is here: a later paste finds no
    owner and gets nothing.
    """
    import os
    import select
    import sys
    import time

    import Xlib.X
    import Xlib.Xatom
    import Xlib.display
    import Xlib.protocol.event

    SELECTION = "${cfg.selection}"
    USERNAME_PASTES = ${toString cfg.usernamePastes}
    PASTE_TIMEOUT = ${toString cfg.pasteTimeoutSeconds}
    CLEAR_SECONDS = ${toString cfg.clearSeconds}
    SETTLE_MS = ${toString cfg.pasteSettleMilliseconds}


    def deadline(seconds):
        """When to give up, or None to wait indefinitely, which is what 0 means."""
        return time.monotonic() + seconds if seconds else None


    def wait(display, until):
        """Block until an event arrives. False if the deadline passed first."""
        while display.pending_events() == 0:
            remaining = None if until is None else until - time.monotonic()
            if remaining is not None and remaining <= 0:
                return False
            if not select.select([display.fileno()], [], [], remaining)[0]:
                return False
        return True


    def answer(display, event, offered, content_targets, value, taken_at):
        """Reply to one selection request. True if it was a paste rather than a query."""
        # A requestor that sends no property is following a convention older than
        # ICCCM, which said to reply into the target atom itself.
        prop = event.property if event.property != Xlib.X.NONE else event.target
        paste = False

        if event.target == offered[0]:
            event.requestor.change_property(prop, Xlib.Xatom.ATOM, 32, offered)
        elif event.target == offered[1]:
            event.requestor.change_property(prop, Xlib.Xatom.INTEGER, 32, [taken_at])
        elif event.target in content_targets:
            event.requestor.change_property(prop, event.target, 8, value.encode())
            paste = True
        else:
            # Refused. A property of None is how a selection owner says no.
            prop = Xlib.X.NONE

        event.requestor.send_event(
            Xlib.protocol.event.SelectionNotify(
                time=event.time, requestor=event.requestor, selection=event.selection,
                target=event.target, property=prop),
            event_mask=0,
        )
        display.flush()
        return paste


    def main():
        payload = sys.stdin.read()
        lines = payload.split("\n")
        if len(lines) >= 2 and lines[1]:
            username, password = lines[0], lines[1]
        else:
            username, password = None, lines[0]

        if not password:
            print("qixos-password-deliver: empty payload", file=sys.stderr)
            return 1

        # A qrexec service inherits none of the user session's X variables, and the
        # qube's session is :0 (qixos core gui.nix).
        display = Xlib.display.Display(os.environ.get("DISPLAY", ":0"))
        window = display.screen().root.create_window(0, 0, 1, 1, 0, Xlib.X.CopyFromParent)

        atom = display.get_atom
        selection = atom(SELECTION.upper())
        # Advertised, not merely accepted. A client picks what it asks for from this
        # list, so a target missing here is a target it will never request.
        offered = [atom("TARGETS"), atom("TIMESTAMP"), atom("UTF8_STRING"),
                   Xlib.Xatom.STRING, atom("TEXT"), atom("text/plain;charset=utf-8"),
                   atom("text/plain")]
        content_targets = {atom("UTF8_STRING"), Xlib.Xatom.STRING, atom("TEXT"),
                           atom("text/plain"), atom("text/plain;charset=utf-8")}

        # A real timestamp rather than CurrentTime, which ICCCM forbids for taking a
        # selection and which leaves nothing truthful to answer TIMESTAMP with.
        # Appending nothing to a property on our own window produces a PropertyNotify
        # carrying a server timestamp, which is the usual way to come by one.
        window.change_attributes(event_mask=Xlib.X.PropertyChangeMask)
        window.change_property(atom("_QIXOS_TIMESTAMP"), Xlib.Xatom.STRING, 8, b"",
                               mode=Xlib.X.PropModeAppend)
        while True:
            event = display.next_event()
            if event.type == Xlib.X.PropertyNotify:
                taken_at = event.time
                break

        window.set_selection_owner(selection, taken_at)
        if display.get_selection_owner(selection) != window:
            print(f"qixos-password-deliver: could not take the {SELECTION}", file=sys.stderr)
            return 1

        pastes = 0
        burst_time = None
        last_content = None
        until = deadline(PASTE_TIMEOUT if username is not None else CLEAR_SECONDS)

        while True:
            if not wait(display, until):
                if username is not None and pastes == 0:
                    # Leaving the username sitting there would be the wrong half of the
                    # credential to abandon in a clipboard.
                    print("qixos-password-deliver: username was never pasted, nothing handed over", file=sys.stderr)
                    return 1
                return 0

            event = display.next_event()

            if event.type == Xlib.X.SelectionClear:
                return 0

            if event.type != Xlib.X.SelectionRequest:
                continue

            value = password

            if username is not None and event.target in content_targets:
                moment = time.monotonic()

                if event.time:
                    # The client stamped the request with the time of the event that
                    # caused it, so every request from one keystroke carries one value.
                    # Elapsed time does not come into it, and a machine that stalls
                    # mid-paste changes nothing.
                    fresh = event.time != burst_time
                    burst_time = event.time
                else:
                    # CurrentTime. The client has told us nothing, so the only thing
                    # separating one paste from the next is the gap between them.
                    fresh = (last_content is None or (moment - last_content) * 1000 > SETTLE_MS)
                    burst_time = None

                last_content = moment

                if fresh:
                    pastes += 1
                    if pastes == USERNAME_PASTES:
                        # The next paste gets the password, so start its clock now
                        # rather than when it is collected.
                        until = deadline(CLEAR_SECONDS)

                # Chosen per request rather than swapped once. A paste can be several
                # requests, and every one of them belongs to the same paste and must be
                # answered the same way.
                value = username if pastes <= USERNAME_PASTES else password

            elif username is not None:
                value = username

            answer(display, event, offered, content_targets, value, taken_at)


    if __name__ == "__main__":
        sys.exit(main())
  '';

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
  # The tests travel with the module but stay inert: they declare nothing unless this
  # module is enabled, and install nothing unless qixosTests.enable is also on. The
  # runner comes along because it is what declares the option the tests assign to, and
  # because a module cannot reach across a flake boundary to find it. If the harness
  # ever becomes its own flake, this module becomes a function of it, in the shape the
  # dev-nube and qixos-admin blueprints already use.
  imports = [
    ../../tests/runner.nix
    ./receiver-tests.nix
  ];

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

    pasteSettleMilliseconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 500;
      description = ''
        How long without a further request before an unstamped paste counts as
        finished.

        Only applies to clients that stamp their requests `CurrentTime`, which says
        nothing about which keystroke caused them. A client that stamps properly is
        grouped by its timestamps instead, whatever the machine is doing.

        Err high. Too long and two deliberate pastes merge, so the username is served
        twice. Too short and one paste splits, so its second half gets the password.
      '';
    };

    usernamePastes = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = ''
        How many times the username has to be pasted before the password replaces it.

        Counted in pastes. A request asking which targets are on offer is negotiation
        and does not count, and several content requests from one keystroke are one
        paste.
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
