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

  mkTest = name: text: pkgs.writeShellApplication {
    inherit name text;
    runtimeInputs = with pkgs; [ coreutils xclip xsel findService ];
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

      password-paste-hands-over-username-then-password =
        mkTest "password-paste-hands-over-username-then-password" ''
          username=alice
          password=s3cret
${waitForX}
          service=$(qixos-find-qrexec-service ${cfg.serviceName})
          xsel --${cfg.selection} --clear

          printf '%s\n%s' "$username" "$password" |
            env -u DISPLAY -u XAUTHORITY "$service"

          # Reading is not a way to watch this from outside: every successful read is
          # one of the requests the handover counts, so they are tallied. A read that
          # finds no owner sends no request and does not count, which is what lets
          # this start before the username is up without changing the answer.
          serves=0
          deadline=$((SECONDS + 30))

          while :; do
            if [ "$SECONDS" -ge "$deadline" ]; then
              echo "password never arrived, after $serves serves of the username" >&2
              exit 1
            fi

            value=$(xclip -selection ${cfg.selection} -out 2>/dev/null) || value=""
            case "$value" in
              "$username") serves=$((serves + 1)) ;;
              "$password") break ;;
              # Either the username is not up yet, or this is the gap between one
              # xclip exiting and the next taking the selection over.
              "") ;;
              *) echo "unexpected selection content: $value" >&2; exit 1 ;;
            esac

            sleep 0.1
          done

          if [ "$serves" -ne ${toString cfg.pasteRequests} ]; then
            echo "handed over after $serves serves, expected ${toString cfg.pasteRequests}" >&2
            exit 1
          fi

          # And it does not linger. No request budget applies to the password, so
          # polling for its removal costs nothing.
          deadline=$((SECONDS + ${toString cfg.clearSeconds} + 30))
          until [ -z "$(xclip -selection ${cfg.selection} -out 2>/dev/null || true)" ]; do
            if [ "$SECONDS" -ge "$deadline" ]; then
              echo "password was never cleared from the ${cfg.selection} selection" >&2
              exit 1
            fi
            sleep 0.2
          done

          echo "handed over after $serves serves, then cleared"
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
