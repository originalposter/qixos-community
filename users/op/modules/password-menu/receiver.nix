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

    ICCCM 2.2 says an owner whose value completely changes should reacquire the
    selection with a new timestamp rather than quietly serve something else, because
    reacquiring is the only thing a client is told about. So each credential gets an
    ownership of its own, and the username's ownership ends the moment it is taken.

    The same section says an owner may answer requests for the value it held during a
    period it owned the selection, even once it no longer owns it. That is what lets the
    handover be immediate: a paste is often several requests, and the ones arriving after
    the handover still carry the timestamp of the keystroke that caused them, so they can
    be answered with the username they were asking for.

    https://tronche.com/gui/x/icccm/sec-2.html
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
    PASTE_TIMEOUT = ${toString cfg.pasteTimeoutSeconds}
    CLEAR_SECONDS = ${toString cfg.clearSeconds}
    SETTLE_MS = ${toString cfg.pasteSettleMilliseconds}
    DEBUG_LOG = ${if cfg.debugLog == null then "None" else ''"${cfg.debugLog}"''}


    def note(line):
        """Record a decision. Never a value: this file is not protected."""
        if DEBUG_LOG:
            with open(DEBUG_LOG, "a") as handle:
                handle.write(f"{time.monotonic():10.3f} pid={os.getpid():<7} {line}\n")


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


    def pump(display, until, queued):
        """The next event, or None if the deadline passes first."""
        if queued:
            return queued.pop(0)
        if not wait(display, until):
            return None
        return display.next_event()


    def own(display, selection, queued, after=Xlib.X.CurrentTime):
        """Take the selection with a fresh window and a real timestamp.

        `after` is a timestamp the new one has to be past, so that the ownership being
        ended provably contains the request that ended it. Timestamps are milliseconds
        and a handover takes less than one, so the two otherwise land on the same value
        often enough to matter. This waits for the server clock rather than inventing a
        value, because SetSelectionOwner is ignored for a time later than the server's
        own and the selection would quietly not change hands.

        Events arriving while we wait for the timestamp are kept rather than dropped.
        """
        window = display.screen().root.create_window(0, 0, 1, 1, 0, Xlib.X.CopyFromParent)
        window.change_attributes(event_mask=Xlib.X.PropertyChangeMask)
        ticker = display.get_atom("_QIXOS_TIMESTAMP")

        # ICCCM forbids CurrentTime for taking a selection, and a property change on our
        # own window is the usual way to be told what the server's clock says.
        window.change_property(ticker, Xlib.Xatom.STRING, 8, b"", mode=Xlib.X.PropModeAppend)

        # A property change on our own window is reported in milliseconds. Not a tuning
        # knob: it is here so a filter that never matches fails instead of hanging.
        OWN_TIMEOUT = 5
        until = deadline(OWN_TIMEOUT)
        while True:
            if not wait(display, until):
                print("qixos-password-deliver: no timestamp from the server", file=sys.stderr)
                return None, None

            event = display.next_event()
            if (event.type == Xlib.X.PropertyNotify
                    and event.atom == ticker
                    and event.window.id == window.id):
                if event.time > after:
                    taken_at = event.time
                    break

                # Still the same millisecond as the request being answered. Ask again.
                window.change_property(ticker, Xlib.Xatom.STRING, 8, b"",
                                       mode=Xlib.X.PropModeAppend)
                continue
            queued.append(event)

        window.set_selection_owner(selection, taken_at)
        if display.get_selection_owner(selection) != window:
            return None, None
        return window, taken_at


    def answer(display, event, offered, content_targets, value, taken_at):
        """Reply to one selection request."""
        # A requestor that sends no property is following a convention older than
        # ICCCM, which said to reply into the target atom itself.
        prop = event.property if event.property != Xlib.X.NONE else event.target

        if event.target == display.get_atom("TARGETS"):
            event.requestor.change_property(prop, Xlib.Xatom.ATOM, 32, offered)
        elif event.target == display.get_atom("TIMESTAMP"):
            event.requestor.change_property(prop, Xlib.Xatom.INTEGER, 32, [taken_at])
        elif event.target in content_targets:
            event.requestor.change_property(prop, event.target, 8, value.encode())
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

        atom = display.get_atom
        selection = atom(SELECTION.upper())
        # Advertised, not merely accepted. A client asks only for what it was offered.
        offered = [atom("TARGETS"), atom("TIMESTAMP"), atom("UTF8_STRING"),
                   Xlib.Xatom.STRING, atom("TEXT"), atom("text/plain;charset=utf-8"),
                   atom("text/plain")]
        content_targets = {atom("UTF8_STRING"), Xlib.Xatom.STRING, atom("TEXT"),
                           atom("text/plain"), atom("text/plain;charset=utf-8")}

        queued = []
        held_from = held_to = None

        window, taken_at = own(display, selection, queued)
        if window is None:
            print(f"qixos-password-deliver: could not take the {SELECTION}", file=sys.stderr)
            return 1
        note(f"took {SELECTION} at {taken_at}, window={window.id} "
             f"username={'yes' if username is not None else 'no'}")

        if username is not None:
            held_from = taken_at
            until = deadline(PASTE_TIMEOUT)
            in_burst = False
            paste_stamp = Xlib.X.CurrentTime

            while True:
                event = pump(display, until, queued)
                if event is None:
                    if in_burst:
                        # An unstamped paste that has gone quiet, so it is over.
                        break

                    note("deadline reached before the username was asked for")
                    print("qixos-password-deliver: username was never pasted, nothing handed over", file=sys.stderr)
                    return 1

                if event.type == Xlib.X.SelectionClear:
                    note("lost the selection to another owner")
                    return 0

                if event.type != Xlib.X.SelectionRequest:
                    continue

                content = event.target in content_targets
                note(f"req={event.requestor.id:<9} time={event.time:<10} "
                     f"target={display.get_atom_name(event.target):<26} "
                     f"{'serving=username' if content else 'negotiation'}")

                answer(display, event, offered, content_targets, username, taken_at)

                if not content:
                    continue

                paste_stamp = event.time

                if event.time != Xlib.X.CurrentTime:
                    # Stamped, so whatever else this paste sends can be recognised
                    # after the handover by the timestamp it carries, and there is
                    # nothing left to wait for.
                    break

                # Unstamped, so the only thing marking the rest of this paste is that
                # it arrives at once. Every request re-arms the wait, which is what
                # holds a burst together.
                in_burst = True
                until = deadline(SETTLE_MS / 1000)

            window, taken_at = own(display, selection, queued, after=paste_stamp)
            if window is None:
                print(f"qixos-password-deliver: could not take the {SELECTION} again",
                      file=sys.stderr)
                return 1
            held_to = taken_at
            note(f"handed over: took {SELECTION} again, window={window.id} at {taken_at}")

        until = deadline(CLEAR_SECONDS)

        while True:
            event = pump(display, until, queued)
            if event is None:
                note("clear time reached")
                return 0

            if event.type == Xlib.X.SelectionClear:
                if event.window.id != window.id:
                    # Our own earlier ownership being retired by the handover.
                    continue
                note("lost the selection to another owner")
                return 0

            if event.type != Xlib.X.SelectionRequest:
                continue

            value = password
            late = False

            # ICCCM 2.2: an owner may answer requests for the value it held while it
            # owned the selection, even once it does not. A request stamped inside the
            # username's ownership belongs to the paste that asked for the username,
            # however long it took to arrive.
            if (held_from is not None
                    and event.time != Xlib.X.CurrentTime
                    and held_from <= event.time <= held_to):
                value = username
                late = True

            served = ("username (late)" if late else "password") \
                if event.target in content_targets else None
            note(f"req={event.requestor.id:<9} time={event.time:<10} "
                 f"target={display.get_atom_name(event.target):<26} "
                 f"{'serving=' + served if served else 'negotiation'}")

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
      default = 250;
      description = ''
        How long without a further request before an unstamped paste counts as
        finished.

        Only applies to clients that stamp their requests `CurrentTime`, which says
        nothing about which keystroke caused them. A client that stamps properly is
        recognised by its timestamps instead, and waits for nothing.

        Every request re-arms it, so a client asking faster than this holds on to the
        username. That is the direction to fail in: the cost is pasting the username
        again, against a password landing in the field it was not meant for.
      '';
    };

    debugLog = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/tmp/qixos-password-deliver.log";
      description = ''
        Where to record what the delivery program was asked and what it decided, or
        null for nowhere.

        For working out why a paste went wrong in an application we have not seen.
        Which client asked, what it asked for, the timestamp it carried, and which
        credential was served. The credentials themselves are never written, but the
        file still says when one was handed over, so keep it off outside debugging.
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
