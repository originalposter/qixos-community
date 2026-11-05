# In-nube tests for the config vault. Pushing from another qube and surviving a reboot
# are an admin test, tests/admin/config_vault_push_survives_reboot.py.
#
# The repo these use is a fixture the nube's own config creates, since the blueprint
# creates none. `repo` below is therefore the suite's name for it, not the module's.
#
# The qrexec hop is stood in for rather than made: each test points GIT_SSH_COMMAND at a
# script that runs the service with the repository as its argument, which is what qrexec
# does on the other side of a policy line. So these exercise the service and git's half
# of the conversation while needing no dom0 policy, in the shape the split-gpg tests use.
{ pkgs, lib, config, ... }:
let
  cfg = config.configVault;
  user = config.services.qubes.core.username;
  vault = "/home/${user}/${cfg.directory}";
  repo = "qixos-community";

  service = "/etc/qubes-rpc/qixos.ReadConfigVault";

  # The argument is taken from the url's path the way the real client takes it, so a test
  # that asked for the wrong repository fails here rather than quietly getting the right
  # one.
  viaService = ''
    cat > "$dir/ssh" <<'SSH'
    #!/bin/sh
    path=''${2#git-upload-pack }
    path=''${path#\'}
    path=''${path%\'}
    exec env QREXEC_SERVICE_ARGUMENT="$(basename "$path" .git)" /etc/qubes-rpc/qixos.ReadConfigVault
    SSH
    chmod +x "$dir/ssh"
    export GIT_SSH_COMMAND="$dir/ssh"
    export GIT_SSH_VARIANT=simple
  '';

  test = name: text: pkgs.writeShellApplication {
    inherit name text;
    runtimeInputs = [ pkgs.git pkgs.coreutils pkgs.gnugrep pkgs.openssh ];
  };
in
{
  qixosTests.tests = {
    # What a template does: fetch the repository dom0 let it ask for.
    config-vault-serves-a-repo-by-name = test "config-vault-serves-a-repo-by-name" ''
      dir=$(mktemp -d)
      trap 'rm -rf "$dir"' EXIT
      ${viaService}

      git clone -q "git+ssh://config-vault.qube/${repo}" "$dir/clone"
      if [ ! -e "$dir/clone/fixture.txt" ]; then
        echo "the clone has no fixture.txt, so what was served was not the fixture" >&2
        ls -a "$dir/clone" >&2
        exit 1
      fi
    '';

    # The ergonomic claim: someone edits files in the vault, commits nothing, and a
    # template building refs/qixos/live gets what is on disk. Mutating, so it puts the
    # fixture back, and it edits a file no other test reads.
    config-vault-serves-the-working-tree = test "config-vault-serves-the-working-tree" ''
      dir=$(mktemp -d)
      restore() {
        git -C ${vault}/${repo} checkout -q -- live.txt 2>/dev/null || true
        rm -f ${vault}/${repo}/untracked-by-the-test
        rm -rf "$dir"
      }
      trap restore EXIT
      ${viaService}

      echo "edited, never committed" > ${vault}/${repo}/live.txt
      echo scratch > ${vault}/${repo}/untracked-by-the-test

      git clone -q "git+ssh://config-vault.qube/${repo}" "$dir/clone"
      git -C "$dir/clone" fetch -q origin refs/qixos/live
      got=$(git -C "$dir/clone" show FETCH_HEAD:live.txt)
      if [ "$got" != "edited, never committed" ]; then
        echo "refs/qixos/live served '$got', not the edit on disk" >&2
        exit 1
      fi
      if ! git -C "$dir/clone" cat-file -e FETCH_HEAD:untracked-by-the-test 2>/dev/null; then
        echo "refs/qixos/live left out a file that was never added" >&2
        exit 1
      fi

      # Committed history stays what was committed, so whoever wants an auditable
      # version gets one by committing and fetching that branch instead.
      if [ "$(git -C "$dir/clone" show origin/master:live.txt)" = "edited, never committed" ]; then
        echo "the branch carries the uncommitted edit, so the snapshot was not separate" >&2
        exit 1
      fi

      # And the person editing sees nothing happen to their checkout.
      if [ -z "$(git -C ${vault}/${repo} status --porcelain)" ]; then
        echo "a fetch cleaned up the vault's own worktree" >&2
        exit 1
      fi

      # A second fetch of an unchanged tree must not move the snapshot. The commit's
      # dates are pinned for this: taking the clock would mint a new sha for the same
      # content, which a puller reads as a change and locks against.
      before=$(git -C ${vault}/${repo} rev-parse refs/qixos/live)
      git -C "$dir/clone" fetch -q origin refs/qixos/live
      if [ "$(git -C ${vault}/${repo} rev-parse refs/qixos/live)" != "$before" ]; then
        echo "fetching an unchanged working tree moved the snapshot" >&2
        exit 1
      fi
    '';

    # The argument is chosen by the calling qube, not by dom0: dom0 only matches it
    # against a rule, and a rule may be `*`. qrexec passes it through without looking at
    # it, splitting the descriptor on `+` and checking its length and nothing else, so
    # the service is what has to refuse a name that points anywhere but at a repo of
    # its own. Set here directly because that is the interface qrexec hands the service,
    # and reaching it any other way would need a second qube and a policy line.
    config-vault-refuses-a-repo-it-does-not-serve = test "config-vault-refuses-a-repo-it-does-not-serve" ''
      for arg in "" "../../etc" "${repo}/.." ".hidden" "no-such-repo"; do
        if QREXEC_SERVICE_ARGUMENT="$arg" ${service} </dev/null >/dev/null 2>&1; then
          echo "the service served something for the argument '$arg'" >&2
          exit 1
        fi
      done

      # The fixture itself has to work, or the loop above proves nothing. upload-pack
      # advertises its refs and then fails on the empty stdin, which is 128.
      status=0
      QREXEC_SERVICE_ARGUMENT="${repo}" ${service} </dev/null >/dev/null 2>&1 || status=$?
      if [ "$status" != 128 ] && [ "$status" != 0 ]; then
        echo "the service did not serve ${repo} either (status $status)" >&2
        exit 1
      fi
    '';

    # Whoever may read may not write, and the read path is upload-pack only, so there is
    # nothing on it to write with.
    config-vault-read-path-cannot-write = test "config-vault-read-path-cannot-write" ''
      dir=$(mktemp -d)
      trap 'rm -rf "$dir"' EXIT
      ${viaService}

      git clone -q "git+ssh://config-vault.qube/${repo}" "$dir/clone"
      git -C "$dir/clone" -c user.name=qixos-test -c user.email=test@qixos.invalid \
        commit -q --allow-empty -m "must not land"
      if git -C "$dir/clone" push -q origin HEAD:refs/heads/through-the-read-path 2>/dev/null; then
        echo "a push went through the read service" >&2
        exit 1
      fi
      if git -C ${vault}/${repo} rev-parse --verify -q refs/heads/through-the-read-path >/dev/null; then
        echo "the push was reported as failed but its ref is in the vault" >&2
        exit 1
      fi
    '';
  }
  # The installed authorized_keys line rather than the option, which is the point: all
  # this blueprint needs of qubes-ssh-server is that it passes the string through
  # untouched, and a version that parsed or normalised keys could drop the forced
  # command and leave a push key with a shell. That failure is silent and in the
  # dangerous direction, so it gets a test of its own.
  // lib.optionalAttrs (cfg.pushKeys != [ ]) {
    config-vault-push-keys-carry-their-restriction = test "config-vault-push-keys-carry-their-restriction" ''
      expected=${lib.escapeShellArg cfg.pushKeyOptions}

      # Gathered first, because grep over a path that does not exist, and head closing
      # the pipe on it, both fail the pipeline under pipefail, and most nubes have no
      # ~/.ssh/authorized_keys at all.
      installed=$(mktemp)
      trap 'rm -f "$installed"' EXIT
      for f in /etc/ssh/authorized_keys.d/* "$HOME/.ssh/authorized_keys"; do
        if [ -e "$f" ]; then cat "$f" >> "$installed"; fi
      done

      check() {
        key=$1
        line=$(grep -F -- "$key" "$installed" | head -1 || true)

        if [ -z "$line" ]; then
          echo "a configured push key is not installed anywhere: $key" >&2
          exit 1
        fi

        case $line in
          "$expected "*) ;;
          *)
            echo "a push key is installed without its forced command:" >&2
            echo "  $line" >&2
            exit 1
            ;;
        esac
      }

${lib.concatMapStringsSep "\n" (k: "      check ${lib.escapeShellArg k}") cfg.pushKeys}
    '';
  }
  # Only where sshd is running, since what is under test is how sshd treats a key
  # installed the way pushKeys installs one.
  // lib.optionalAttrs config.services.openssh.enable {
    # A key carrying pushKeyOptions can push and can do nothing else.
    #
    # The key is generated here and added to the account's own authorized_keys rather
    # than asserted on as configuration, because reading the option back would only
    # prove the string is what this file says it is. What can be got wrong is sshd's
    # treatment of it, so sshd is what gets asked, with the option string taken from the
    # blueprint so the two cannot drift. Generating the key here also keeps a private
    # half out of the store, which a cluster shares.
    #
    # Mutating. It appends to ~/.ssh/authorized_keys and restores it afterwards. A
    # failure part way through leaves a public key whose private half was in a temp
    # directory that is gone, so it grants nothing.
    config-vault-push-key-cannot-run-commands = test "config-vault-push-key-cannot-run-commands" ''
      dir=$(mktemp -d)
      marker="$dir/a-command-ran"
      authorized="$HOME/.ssh/authorized_keys"

      restore() {
        if [ -e "$dir/backup" ]; then
          cp "$dir/backup" "$authorized"
        else
          rm -f "$authorized"
        fi
        git -C ${vault}/${repo} update-ref -d refs/heads/push-key-test 2>/dev/null || true
        rm -rf "$dir"
      }
      trap restore EXIT

      mkdir -p "$HOME/.ssh"
      chmod 700 "$HOME/.ssh"
      if [ -e "$authorized" ]; then cp "$authorized" "$dir/backup"; fi

      ssh-keygen -q -t ed25519 -N "" -C config-vault-test -f "$dir/key"
      printf '%s %s\n' ${lib.escapeShellArg cfg.pushKeyOptions} "$(cat "$dir/key.pub")" \
        >> "$authorized"
      chmod 600 "$authorized"

      ssh_opts=(
        -i "$dir/key"
        -o IdentitiesOnly=yes
        -o IdentityAgent=none
        -o BatchMode=yes
        -o StrictHostKeyChecking=no
        -o UserKnownHostsFile=/dev/null
        -o LogLevel=ERROR
        -p ${toString config.qubesSshServer.port}
      )

      # The forced command runs instead of this and then fails on an empty stdin, so its
      # exit status says nothing. Whether the marker exists does.
      #
      # shellcheck disable=SC2029  # expanding $marker here is the point: same machine
      # -n only here, never in ssh_opts: a push needs the stdin this closes.
      ssh -n "''${ssh_opts[@]}" 127.0.0.1 "touch $marker" >/dev/null 2>&1 || true
      if [ -e "$marker" ]; then
        echo "a push key ran a shell command on the vault" >&2
        exit 1
      fi

      git init -q "$dir/work"
      git -C "$dir/work" -c user.name=qixos-test -c user.email=test@qixos.invalid \
        commit -q --allow-empty -m "pushed by a restricted key"

      if ! GIT_SSH_COMMAND="ssh ''${ssh_opts[*]}" git -C "$dir/work" \
          push -q "ssh://127.0.0.1${vault}/${repo}" HEAD:refs/heads/push-key-test 2>"$dir/err"; then
        echo "a push key could not push:" >&2
        cat "$dir/err" >&2
        exit 1
      fi

      if ! git -C ${vault}/${repo} rev-parse --verify -q refs/heads/push-key-test >/dev/null; then
        echo "the push reported success but its ref is not in the vault" >&2
        exit 1
      fi

      # A repo the key has no business in, named by absolute path so nothing but the
      # wrapper's own check can stop it. The message has to be the wrapper's: a push
      # refused for any other reason would pass a test that only read the status.
      outside="$dir/outside.git"
      git init -q --bare "$outside"
      if GIT_SSH_COMMAND="ssh ''${ssh_opts[*]}" git -C "$dir/work" \
          push -q "ssh://127.0.0.1$outside" HEAD:refs/heads/escaped 2>"$dir/escape-err"; then
        echo "a push key pushed to $outside, outside the vault" >&2
        exit 1
      fi
      if ! grep -q "refusing a repository outside" "$dir/escape-err"; then
        echo "the push outside the vault failed, but not by being refused:" >&2
        cat "$dir/escape-err" >&2
        exit 1
      fi
    '';
  };
}
