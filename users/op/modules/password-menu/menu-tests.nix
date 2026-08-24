# Tests for menu.nix, which imports this file. Declared only when the menu is enabled,
# and installed when qixosTests.enable is on.
#
# Each test works the same way. It builds a scratch directory holding a fake password
# store, stand-ins for the three programs the menu shells out to, and the files those
# stand-ins read and write. Then it runs the menu against them and looks at what was
# recorded.
#
# The stand-ins exist because the real programs cannot be driven here: rofi wants a
# person to pick something, and qrexec-client-vm wants a dom0 policy. Standing in for
# qrexec is also the only way to see the payload, which is the thing most worth pinning,
# since it is the wire format receiver.nix parses.
#
# `pass` is stood in for as well. What is under test is which entry gets chosen and what
# gets sent, and a real store would add a gpg key to generate and an agent to talk to
# without covering any more of that. The stand-in records how it was called, which is
# the part that would otherwise go untested.
{ pkgs, lib, config, ... }:
let
  cfg = config.qubesPasswordMenu;

  sep = cfg.usernameSeparator;

  # The three programs the menu shells out to, written out exactly as they appear here.
  # Each finds its files through QIXOS_TEST, which the fixture exports before running the
  # menu, so none of them needs a path substituted into it.

  # rofi -dmenu takes the entry list on stdin and prints the one the user picked.
  rofiStandIn = ''
    #!/bin/sh
    cat > "$QIXOS_TEST/offered"
    cat "$QIXOS_TEST/chosen"
  '';

  # `pass show <entry>` prints the entry, whose first line is the password.
  passStandIn = ''
    #!/bin/sh
    echo "$*" >> "$QIXOS_TEST/asked-pass"
    cat "$QIXOS_TEST/entry-body"
  '';

  # `qubesdb-read /name` is how a qube learns the name it is known by. The name it
  # answers with here is deliberately not a plausible destination: the menu is supposed
  # to name itself and let dom0 redirect, so a test that saw a destination name would be
  # seeing a bug.
  qubesdbStandIn = ''
    #!/bin/sh
    echo "$*" >> "$QIXOS_TEST/asked-qubesdb"
    echo the-calling-qube
  '';

  # `qrexec-client-vm <target> <service>` takes the payload on stdin.
  qrexecStandIn = ''
    #!/bin/sh
    echo "$*" > "$QIXOS_TEST/called-qrexec"
    cat > "$QIXOS_TEST/sent"
  '';

  fixture = ''
    scratch=$(mktemp -d)
    trap 'rm -rf "$scratch"' EXIT

    # The stand-ins read this out of the environment, which the menu passes on to them
    # when it shells out.
    export QIXOS_TEST=$scratch

    stand_ins=$scratch/stand-ins
    store=$scratch/store
    mkdir -p "$stand_ins" "$store/web"

    # What the stand-ins are told to do.
    chosen=$QIXOS_TEST/chosen          # the entry rofi will pick
    entry_body=$QIXOS_TEST/entry-body  # what pass will print for it

    # What they recorded, which is what the tests then read.
    offered=$QIXOS_TEST/offered              # the entry list rofi was shown
    asked_pass=$QIXOS_TEST/asked-pass        # the arguments pass was called with
    called_qrexec=$QIXOS_TEST/called-qrexec  # the arguments qrexec-client-vm was called with
    asked_qubesdb=$QIXOS_TEST/asked-qubesdb  # the arguments qubesdb-read was called with
    sent=$QIXOS_TEST/sent                    # the payload, on qrexec's stdin

    printf '%s' ${lib.escapeShellArg rofiStandIn} > "$stand_ins/rofi"
    printf '%s' ${lib.escapeShellArg passStandIn} > "$stand_ins/pass"
    printf '%s' ${lib.escapeShellArg qrexecStandIn} > "$stand_ins/qrexec-client-vm"
    printf '%s' ${lib.escapeShellArg qubesdbStandIn} > "$stand_ins/qubesdb-read"
    chmod +x "$stand_ins/rofi" "$stand_ins/pass" "$stand_ins/qrexec-client-vm" \
      "$stand_ins/qubesdb-read"

    # Two lines, so a test can tell whether anything past the first was sent.
    printf 's3cret\nrecovery code: 1234\n' > "$entry_body"

    # writeShellApplication bakes `export PATH="<runtimeInputs>:$PATH"` into the menu, so
    # a stand-in placed in the environment loses to the real rofi. Copying the menu and
    # inserting a second export straight after that line puts the stand-ins in front.
    # Every line below the insertion is the menu exactly as shipped.
    #
    # The count check matters. If nixpkgs ever writes that preamble differently the
    # insertion silently stops happening, and these tests would run the real rofi and
    # hang rather than fail.

    menu=$scratch/menu-under-test

    # -v is how the shell value gets in: awk cannot see the variables of the shell that
    # started it. No apostrophes below, which would close the quoting around the program.

    awk -v stand_ins="$stand_ins" '

      # Copy the menu through a line at a time. Rules run in order against each line, so
      # this one has already printed the original by the time the next one adds to it.

      { print }

      # The insertion, directly after the line just printed. A later export wins, so the
      # stand-ins end up ahead of runtimeInputs. Only on the first match: a menu that
      # sets PATH again further down should keep doing so.

      /^export PATH=/ {
        seen += 1
        if (seen == 1) print "export PATH=\"" stand_ins ":$PATH\""
      }

      # Zero matches means nothing was inserted and the test would quietly run the real
      # rofi. More than one means the shape assumed here is wrong. Neither is worth
      # producing a script for.

      END {
        if (seen != 1) {
          print "expected one export PATH line in the menu, found " seen > "/dev/stderr"
          exit 1
        }
      }
    ' "$(command -v qixos-password-menu)" > "$menu"

    chmod +x "$menu"
  '';

  mkTest = name: text: pkgs.writeShellApplication {
    inherit name text;
    runtimeInputs = with pkgs; [ coreutils diffutils gawk gnugrep ];

    # SC2016 fires on the stand-ins being written out in single quotes, which is what
    # gets them onto disk verbatim: `$QIXOS_TEST` and `$*` are for the stand-in to
    # expand when it runs, not for this script to expand while writing it.
    #
    # SC2034 fires because the fixture names every file it lays out and no single test
    # reads all of them.
    excludeShellChecks = [ "SC2016" "SC2034" ];
  };
in
{
  config = lib.mkIf cfg.enable {
    qixosTests.tests = {

      # The wire format receiver.nix parses: username, one newline, password, nothing
      # after it. Compared byte for byte, so a changed separator or a stray trailing
      # newline fails here rather than in a browser.
      password-menu-sends-the-username-then-the-password =
        mkTest "password-menu-sends-the-username-then-the-password" ''
${fixture}
          : > "$store/web/example.com${sep}alice.gpg"
          echo 'web/example.com${sep}alice' > "$chosen"

          PASSWORD_STORE_DIR="$store" "$menu" --with-username

          printf 'alice\ns3cret' > "$scratch/want"
          if ! cmp -s "$sent" "$scratch/want"; then
            echo "sent:" >&2
            od -c < "$sent" >&2
            echo "expected the username, one newline, then the entry's first line" >&2
            exit 1
          fi

          echo "sent username, newline, password"
        '';

      # The call names this qube rather than the destination, and dom0 redirects it. A
      # request has to name a qube the policy admits, and its own name is the only one
      # the menu can know. It is also what makes the arrangement fail closed: a qube
      # cannot qrexec to itself, so a policy that stopped redirecting would kill the call
      # instead of delivering somewhere unintended.
      #
      # Both ways of sending are checked because they are two separate call sites, and
      # nothing but this stops one of them drifting.
      password-menu-names-this-qube-to-dom0 =
        mkTest "password-menu-names-this-qube-to-dom0" ''
${fixture}
          : > "$store/web/example.com${sep}alice.gpg"
          echo 'web/example.com${sep}alice' > "$chosen"

          PASSWORD_STORE_DIR="$store" "$menu" --with-username
          if [ "$(cat "$called_qrexec")" != "the-calling-qube ${cfg.serviceName}" ]; then
            echo "with a username, called qrexec as '$(cat "$called_qrexec")'" >&2
            echo "expected 'the-calling-qube ${cfg.serviceName}', this qube naming itself" >&2
            exit 1
          fi

          PASSWORD_STORE_DIR="$store" "$menu"
          if [ "$(cat "$called_qrexec")" != "the-calling-qube ${cfg.serviceName}" ]; then
            echo "without a username, called qrexec as '$(cat "$called_qrexec")'" >&2
            echo "expected 'the-calling-qube ${cfg.serviceName}', this qube naming itself" >&2
            exit 1
          fi

          # Both runs appended, so every line should be the same question.
          if [ "$(sort -u "$asked_qubesdb")" != "/name" ]; then
            echo "asked qubesdb for $(sort -u "$asked_qubesdb" | tr '\n' ' '), expected /name" >&2
            exit 1
          fi

          echo "named itself to dom0 both ways, service ${cfg.serviceName}"
        '';

      # Without the flag the payload is a single line, which is the shape that tells the
      # receiver to serve the password straight away and skip the handover.
      password-menu-without-the-flag-sends-only-the-password =
        mkTest "password-menu-without-the-flag-sends-only-the-password" ''
${fixture}
          : > "$store/web/example.com${sep}alice.gpg"
          echo 'web/example.com${sep}alice' > "$chosen"

          PASSWORD_STORE_DIR="$store" "$menu"

          printf 's3cret' > "$scratch/want"
          if ! cmp -s "$sent" "$scratch/want"; then
            echo "sent:" >&2
            od -c < "$sent" >&2
            echo "expected the entry's first line alone, with no username" >&2
            exit 1
          fi

          echo "sent the password alone"
        '';

      # Anything after the last separator is the username, so a service name may contain
      # one. The entry is still looked up under its whole name.
      password-menu-username-is-what-follows-the-last-separator =
        mkTest "password-menu-username-is-what-follows-the-last-separator" ''
${fixture}
          entry=web/plus${sep}in${sep}name${sep}bob
          : > "$store/$entry.gpg"
          echo "$entry" > "$chosen"

          PASSWORD_STORE_DIR="$store" "$menu" --with-username

          printf 'bob\ns3cret' > "$scratch/want"
          if ! cmp -s "$sent" "$scratch/want"; then
            echo "sent:" >&2
            od -c < "$sent" >&2
            echo "expected bob, the part after the last ${sep}" >&2
            exit 1
          fi

          if [ "$(cat "$asked_pass")" != "show $entry" ]; then
            echo "asked pass for '$(cat "$asked_pass")', expected 'show $entry'" >&2
            echo "the separator says where the username starts, it does not shorten the entry" >&2
            exit 1
          fi

          echo "username taken from after the last ${sep}, entry looked up whole"
        '';

      # A hard error rather than a quiet fall back to password-only. The caller asked for
      # a username, and sending without one puts the password in the username field.
      password-menu-refuses-an-entry-without-a-username =
        mkTest "password-menu-refuses-an-entry-without-a-username" ''
${fixture}
          : > "$store/nosep.gpg"
          echo 'nosep' > "$chosen"

          if PASSWORD_STORE_DIR="$store" "$menu" --with-username 2> "$scratch/err"; then
            echo "an entry with no ${sep} was accepted under --with-username" >&2
            exit 1
          fi

          if ! grep -q 'is not of the form' "$scratch/err"; then
            echo "failed with '$(cat "$scratch/err")', expected a complaint about the form" >&2
            exit 1
          fi

          if [ -e "$sent" ]; then
            echo "refused the entry and sent something anyway:" >&2
            od -c < "$sent" >&2
            exit 1
          fi

          # The check sits above `pass show`, so a malformed name never reaches gpg.
          if [ -e "$asked_pass" ]; then
            echo "decrypted $(cat "$asked_pass") before refusing it" >&2
            exit 1
          fi

          echo "refused an entry with no ${sep}, nothing decrypted and nothing sent"
        '';
    };
  };
}
