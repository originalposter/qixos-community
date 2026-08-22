# Tests for receiver.nix, which imports this file. Declared only when
# the receiver is enabled, so a nube that imports the module and leaves it off does not
# advertise tests that could not pass, and installed only when qixosTests.enable is on.
#
# These need a real X session, which is why they are in-nube tests rather than
# something the suite could evaluate from outside. They do not need the vault: the
# service is fed on stdin the same way qrexec feeds it.
#
# Mutating. Each one takes over this nube's selection, so do not run them in a qube
# whose clipboard someone is using.
{ pkgs, lib, config, ... }:
let
  cfg = config.qubesPasswordReceiver;

  # Nothing is installed to /etc/qubes-rpc: qixos core builds a QREXEC_SERVICE_PATH
  # from services.qubes.qrexec.packages and puts it on the agent's unit
  # (qubes-modules/qrexec.nix), so the running unit is the only honest place to ask
  # where a service ended up.
  findService = pkgs.writeShellApplication {
    name = "qixos-find-qrexec-service";
    runtimeInputs = with pkgs; [ coreutils gnused systemd ];
    text = ''
      if [ "$#" -ne 1 ]; then
        echo "usage: qixos-find-qrexec-service <service-name>" >&2
        exit 2
      fi

      search=$(systemctl show --property=Environment --value qubes-qrexec-agent.service |
        tr ' ' '\n' | sed -n 's/^QREXEC_SERVICE_PATH=//p')

      if [ -z "$search" ]; then
        echo "qubes-qrexec-agent.service has no QREXEC_SERVICE_PATH" >&2
        exit 1
      fi

      IFS=: read -ra dirs <<< "$search"
      for dir in "''${dirs[@]}"; do
        if [ -x "$dir/$1" ]; then
          echo "$dir/$1"
          exit 0
        fi
      done

      echo "no qrexec service named $1 in $search" >&2
      exit 1
    '';
  };

  # These run over ssh, which has no session of its own, and a nube answers ssh some
  # seconds before its X server is up. The wait lives here rather than in the runner
  # because needing an X server is a property of these tests, not of in-nube tests.
  waitForX = ''
    deadline=$((SECONDS + 60))
    until [ -e /tmp/.X11-unix/X0 ]; do
      if [ "$SECONDS" -ge "$deadline" ]; then
        echo "no X server on this nube after 60s" >&2
        exit 1
      fi
      sleep 1
    done

    # For reading the selection. The service deliberately does not get this below,
    # because inheriting no X variables is the case it has to cope with in production.
    export DISPLAY="''${DISPLAY:-:0}"
  '';

  # Asks for the selection the way a browser does, with control over the one thing that
  # separates a paste from the next one: the X timestamp on each request. A requestor is
  # supposed to stamp a request with the time of the event that caused it, so requests
  # sharing a timestamp are one keystroke's worth however many there are.
  #
  # xclip cannot express this. Every invocation is a fresh process with a fresh
  # timestamp, so a burst emulated with it is indistinguishable from separate pastes
  # except by wall clock, which is exactly the guessing the receiver is trying to avoid.
  #
  #   qixos-request-selection 2 --one-paste     two requests under one timestamp
  #   qixos-request-selection 2                 two requests, two timestamps
  #   qixos-request-selection 2 --current-time  two requests stamped CurrentTime
  #   qixos-request-selection 2 --one-paste --delay 2
  #                                             one timestamp, two seconds apart
  #
  # The last is how chromium asks: it stamps every request 0, so the timestamps say
  # nothing and the requests can only be counted.
  #
  # Prints what each request was served, one per line.
  requestSelection = pkgs.writers.writePython3Bin "qixos-request-selection" {
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
    """Request an X selection a given number of times, controlling the timestamps."""
    import os
    import sys
    import time

    import Xlib.X
    import Xlib.Xatom
    import Xlib.display

    count = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    one_paste = "--one-paste" in sys.argv
    current_time = "--current-time" in sys.argv
    delay = float(sys.argv[sys.argv.index("--delay") + 1]) if "--delay" in sys.argv else 0.0

    display = Xlib.display.Display(os.environ.get("DISPLAY", ":0"))
    window = display.screen().root.create_window(0, 0, 1, 1, 0, Xlib.X.CopyFromParent)
    window.change_attributes(event_mask=Xlib.X.PropertyChangeMask)

    atom = display.get_atom
    selection = atom("CLIPBOARD")
    target = atom("UTF8_STRING")
    result = atom("_QIXOS_RESULT")
    ticker = atom("_QIXOS_TICKER")


    def now():
        """A server timestamp, from a property change on our own window."""
        window.change_property(ticker, Xlib.Xatom.STRING, 8, b"", mode=Xlib.X.PropModeAppend)
        while True:
            event = display.next_event()
            if event.type == Xlib.X.PropertyNotify and event.atom == ticker:
                return event.time


    stamp = now() if one_paste else None

    for index in range(count):
        if index and delay:
            time.sleep(delay)

        if current_time:
            when = Xlib.X.CurrentTime
        else:
            when = stamp if one_paste else now()
        window.convert_selection(selection, target, result, when)

        while True:
            event = display.next_event()
            if event.type == Xlib.X.SelectionNotify:
                break

        if event.property == Xlib.X.NONE:
            print("refused")
            continue

        value = window.get_full_property(result, Xlib.X.AnyPropertyType)
        print(value.value.decode() if value else "")
        window.delete_property(result)
  '';

  mkTest = name: text: pkgs.writeShellApplication {
    inherit name text;
    runtimeInputs = with pkgs; [ coreutils xclip xsel findService requestSelection ];
  };
in
{
  config = lib.mkIf cfg.enable {
    qixosTests.tests = {

      password-paste-service-registered =
        mkTest "password-paste-service-registered" ''
          service=$(qixos-find-qrexec-service ${cfg.serviceName})
          echo "registered at $service"
        '';

      # The property that matters, and the one a request count cannot express: asking
      # what targets are on offer is a negotiation, not a paste. Firefox asks for the
      # text alone and chromium asks for the targets first, so a handover keyed on the
      # number of selection requests is right for one browser and wrong for the other.
      #
      # Deliberately says nothing about how many requests a paste takes. It plants a
      # credential, negotiates several times, and then asserts that the first read of
      # the content is the username and the second is the password.
      password-paste-hands-over-username-then-password =
        mkTest "password-paste-hands-over-username-then-password" ''
          username=alice
          password=s3cret
${waitForX}
          service=$(qixos-find-qrexec-service ${cfg.serviceName})
          xsel --${cfg.selection} --clear

          printf '%s\n%s' "$username" "$password" |
            env -u DISPLAY -u XAUTHORITY "$service"

          # Waiting for the selection to be taken, by asking only what is on offer.
          # Reading the content here would be a paste and would move the handover on.
          deadline=$((SECONDS + 30))
          until xclip -selection ${cfg.selection} -out -target TARGETS >/dev/null 2>&1; do
            if [ "$SECONDS" -ge "$deadline" ]; then
              echo "nothing took the ${cfg.selection} within 30s" >&2
              exit 1
            fi
            sleep 0.2
          done

          # Two more, standing in for a toolkit that negotiates before every paste.
          xclip -selection ${cfg.selection} -out -target TARGETS >/dev/null
          xclip -selection ${cfg.selection} -out -target TARGETS >/dev/null

          first=$(xclip -selection ${cfg.selection} -out)
          if [ "$first" != "$username" ]; then
            if [ "$first" = "$password" ]; then
              echo "the password was handed over before the username was ever pasted" >&2
            else
              echo "first paste gave '$first', expected the username" >&2
            fi
            exit 1
          fi


          # xclip stamps its requests CurrentTime, so it is grouped by the settle
          # window rather than by keystroke. Two reads back to back are one paste by
          # design, which is what password-paste-groups-unstamped-requests-by-time
          # asserts. Waiting past the window is what makes this a second paste, and it
          # is what a person moving between two fields does anyway.
          sleep ${toString (cfg.pasteSettleMilliseconds / 1000 + 1)}
          second=$(xclip -selection ${cfg.selection} -out)
          if [ "$second" != "$password" ]; then
            echo "second paste gave '$second', expected the password" >&2
            exit 1
          fi

          echo "negotiation ignored, then username, then password"
        '';

      # The shape that made the password land in a username field. Chromium asks which
      # targets are on offer and then asks for the text, so one paste is two selection
      # requests. Anything counting requests spends its budget on the negotiation and
      # serves the password to the fetch that follows.
      #
      # `xclip -out` on its own is that pattern, and `-target UTF8_STRING` is the fetch
      # without the negotiation, so the two halves can be issued separately here.
      password-paste-negotiation-then-fetch-is-one-paste =
        mkTest "password-paste-negotiation-then-fetch-is-one-paste" ''
          username=alice
          password=s3cret
${waitForX}
          service=$(qixos-find-qrexec-service ${cfg.serviceName})
          xsel --${cfg.selection} --clear

          printf '%s\n%s' "$username" "$password" |
            env -u DISPLAY -u XAUTHORITY "$service"

          deadline=$((SECONDS + 30))
          until xclip -selection ${cfg.selection} -out -target TARGETS >/dev/null 2>&1; do
            if [ "$SECONDS" -ge "$deadline" ]; then
              echo "nothing took the ${cfg.selection} within 30s" >&2
              exit 1
            fi
            sleep 0.2
          done

          # One paste, the way chromium makes it.
          xclip -selection ${cfg.selection} -out -target TARGETS >/dev/null
          first=$(xclip -selection ${cfg.selection} -out -target UTF8_STRING)
          if [ "$first" = "$password" ]; then
            echo "the negotiation was counted as the paste, so the password went where the username belongs" >&2
            exit 1
          elif [ "$first" != "$username" ]; then
            echo "first paste gave '$first', expected the username" >&2
            exit 1
          fi

          # A second one, which is what should bring the password.

          # xclip stamps its requests CurrentTime, so it is grouped by the settle
          # window rather than by keystroke. Two reads back to back are one paste by
          # design, which is what password-paste-groups-unstamped-requests-by-time
          # asserts. Waiting past the window is what makes this a second paste, and it
          # is what a person moving between two fields does anyway.
          sleep ${toString (cfg.pasteSettleMilliseconds / 1000 + 1)}
          xclip -selection ${cfg.selection} -out -target TARGETS >/dev/null
          second=$(xclip -selection ${cfg.selection} -out -target UTF8_STRING)
          if [ "$second" != "$password" ]; then
            echo "second paste gave '$second', expected the password" >&2
            exit 1
          fi

          echo "negotiate-then-fetch counted once, twice over"
        '';

      # Firefox asks for the content twice for a single paste, a few milliseconds
      # apart, with both requests carrying the timestamp of the keystroke that caused
      # them. Counting requests therefore hands the password to the second half of the
      # first paste, which is the password landing in a username field.
      #
      # Not expressible with xclip: each invocation is its own process with its own
      # timestamp, so a burst and two separate pastes look identical to it.
      password-paste-serves-one-burst-once =
        mkTest "password-paste-serves-one-burst-once" ''
          username=alice
          password=s3cret
${waitForX}
          service=$(qixos-find-qrexec-service ${cfg.serviceName})
          xsel --${cfg.selection} --clear

          printf '%s\n%s' "$username" "$password" |
            env -u DISPLAY -u XAUTHORITY "$service"

          deadline=$((SECONDS + 30))
          until xclip -selection ${cfg.selection} -out -target TARGETS >/dev/null 2>&1; do
            if [ "$SECONDS" -ge "$deadline" ]; then
              echo "nothing took the ${cfg.selection} within 30s" >&2
              exit 1
            fi
            sleep 0.2
          done

          # One paste, the way firefox makes it: two requests, one timestamp.
          burst=$(qixos-request-selection 2 --one-paste)
          if [ "$burst" != "$username
$username" ]; then
            echo "one paste of two requests served: $burst" >&2
            echo "expected the username twice, since it is a single paste" >&2
            exit 1
          fi

          # The next keystroke is a new timestamp, and should bring the password.
          next=$(qixos-request-selection 1)
          if [ "$next" != "$password" ]; then
            echo "the paste after the first gave '$next', expected the password" >&2
            exit 1
          fi

          echo "two requests under one timestamp counted once"
        '';

      # Chromium stamps every request CurrentTime, so the timestamps say nothing and
      # requests can only be told apart by when they arrived. Two of them back to back
      # are one paste; one after the settle window is the next.
      #
      # This is the only test with a sleep in it, and the thing it sleeps past is the
      # window itself rather than a guess about how long something takes.
      password-paste-groups-unstamped-requests-by-time =
        mkTest "password-paste-groups-unstamped-requests-by-time" ''
          username=alice
          password=s3cret
${waitForX}
          service=$(qixos-find-qrexec-service ${cfg.serviceName})
          xsel --${cfg.selection} --clear

          printf '%s\n%s' "$username" "$password" |
            env -u DISPLAY -u XAUTHORITY "$service"

          deadline=$((SECONDS + 30))
          until xclip -selection ${cfg.selection} -out -target TARGETS >/dev/null 2>&1; do
            if [ "$SECONDS" -ge "$deadline" ]; then
              echo "nothing took the ${cfg.selection} within 30s" >&2
              exit 1
            fi
            sleep 0.2
          done

          burst=$(qixos-request-selection 2 --current-time)
          if [ "$burst" != "$username
$username" ]; then
            echo "two unstamped requests back to back served: $burst" >&2
            echo "expected the username twice, since nothing separates them" >&2
            exit 1
          fi

          # Past the window, so the next one is a different paste.
          sleep ${toString (cfg.pasteSettleMilliseconds / 1000 + 1)}

          next=$(qixos-request-selection 1 --current-time)
          if [ "$next" != "$password" ]; then
            echo "the request after the settle window gave '$next', expected the password" >&2
            exit 1
          fi

          echo "unstamped requests grouped by the settle window"
        '';

      # The claim the hybrid rests on: a client that stamps its requests says which
      # keystroke caused each one, so elapsed time must not enter into grouping them.
      # Two requests under one timestamp are one paste even if the machine stalled for
      # longer than the settle window between them.
      #
      # Without this, nothing stops the timestamp path quietly degrading into the timing
      # path, which would put the lag failure back for every client.
      password-paste-stamped-requests-ignore-the-settle-window =
        mkTest "password-paste-stamped-requests-ignore-the-settle-window" ''
          username=alice
          password=s3cret
${waitForX}
          service=$(qixos-find-qrexec-service ${cfg.serviceName})
          xsel --${cfg.selection} --clear

          printf '%s\n%s' "$username" "$password" |
            env -u DISPLAY -u XAUTHORITY "$service"

          deadline=$((SECONDS + 30))
          until xclip -selection ${cfg.selection} -out -target TARGETS >/dev/null 2>&1; do
            if [ "$SECONDS" -ge "$deadline" ]; then
              echo "nothing took the ${cfg.selection} within 30s" >&2
              exit 1
            fi
            sleep 0.2
          done

          burst=$(qixos-request-selection 2 --one-paste --delay ${toString (cfg.pasteSettleMilliseconds / 1000 + 2)})
          if [ "$burst" != "$username
$username" ]; then
            echo "one timestamp, spread past the settle window, served: $burst" >&2
            echo "expected the username twice: the timestamp says it is one paste" >&2
            exit 1
          fi

          next=$(qixos-request-selection 1)
          if [ "$next" != "$password" ]; then
            echo "the paste after it gave '$next', expected the password" >&2
            exit 1
          fi

          echo "one timestamp stayed one paste across the settle window"
        '';

      password-paste-clears-when-nobody-pastes =
        mkTest "password-paste-clears-when-nobody-pastes" ''
${waitForX}
          service=$(qixos-find-qrexec-service ${cfg.serviceName})
          xsel --${cfg.selection} --clear

          printf 'alice\ns3cret' | env -u DISPLAY -u XAUTHORITY "$service"

          # Nothing reads the selection during the wait, on purpose. A read here would
          # be a paste, and would send the test down the other path.
          sleep $((${toString cfg.pasteTimeoutSeconds} + 5))

          left=$(xclip -selection ${cfg.selection} -out 2>/dev/null || true)
          if [ -n "$left" ]; then
            echo "expected an empty selection, found: $left" >&2
            exit 1
          fi

          echo "gave up and cleared, password never handed over"
        '';
    };
  };
}
