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
{ pkgs, config, ... }:
let
  cfg = config.configVault;
  user = config.services.qubes.core.username;
  vault = "/home/${user}/${cfg.directory}";
  repo = "qixos-community";

  readService = "/etc/qubes-rpc/qixos.ReadConfigVault";
  writeService = "/etc/qubes-rpc/qixos.WriteConfigVault";

  # The stand-in for the qrexec hop: git invokes it the way it invokes ssh, and it hands
  # the repository to the service as its argument, which is what qrexec does on the other
  # side of a policy line. `route` picks which service a push reaches, so a test can send
  # one at the read service to watch it refused.
  shim = route: ''
    cat > "$dir/ssh" <<'SSH'
    #!/bin/sh
    case $2 in
      "git-upload-pack "*)  service=${readService}; path=''${2#git-upload-pack } ;;
      "git-receive-pack "*) service=${route};       path=''${2#git-receive-pack } ;;
      *) echo "not a git request: $2" >&2; exit 1 ;;
    esac
    path=''${path#\'}
    path=''${path%\'}
    exec env QREXEC_SERVICE_ARGUMENT="$(basename "$path" .git)" "$service"
    SSH
    chmod +x "$dir/ssh"
    export GIT_SSH_COMMAND="$dir/ssh"
    export GIT_SSH_VARIANT=simple
  '';

  viaService = shim writeService;
  viaReadServiceOnly = shim readService;

  test = name: text: pkgs.writeShellApplication {
    inherit name text;
    runtimeInputs = [ pkgs.git pkgs.coreutils pkgs.gnugrep ];
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

    # The push side is a service of its own, so a dom0 line granting it says what it
    # grants: pushing to one repository, with no sshd and no key, since the calling qube
    # is the principal and dom0 decides which qube that may be.
    config-vault-accepts-a-push-through-the-service = test "config-vault-accepts-a-push-through-the-service" ''
      dir=$(mktemp -d)
      ref=refs/heads/pushed-through-the-service
      # Both ends: the repo outlives the nube's boot, so a run that left this behind
      # would hand the next run a ref it did not create.
      drop() { git -C ${vault}/${repo} update-ref -d "$ref" 2>/dev/null || true; }
      # The branch and the worktree are the fixture's, so put both back: this test is
      # the one that moves them.
      was=$(git -C ${vault}/${repo} rev-parse HEAD)
      cleanup() {
        drop
        git -C ${vault}/${repo} reset -q --hard "$was" 2>/dev/null || true
        rm -rf "$dir"
      }
      drop
      trap cleanup EXIT
      ${viaService}

      git clone -q "git+ssh://config-vault.qube/${repo}" "$dir/clone"
      git -C "$dir/clone" -c user.name=qixos-test -c user.email=test@qixos.invalid \
        commit -q --allow-empty -m "pushed through the write service"
      sha=$(git -C "$dir/clone" rev-parse HEAD)

      if ! git -C "$dir/clone" push -q origin "HEAD:$ref" 2>"$dir/err"; then
        echo "the push through the write service failed:" >&2
        cat "$dir/err" >&2
        exit 1
      fi

      got=$(git -C ${vault}/${repo} rev-parse --verify -q "$ref" || true)
      if [ "$got" != "$sha" ]; then
        echo "the vault has '$got' for the pushed ref, expected $sha" >&2
        exit 1
      fi

      # Pushing the branch the vault has checked out, which is the case the vault
      # configures receive.denyCurrentBranch for and the one the changelog promises:
      # it lands while the vault's own worktree is clean, and the worktree follows.
      git -C "$dir/clone" -c user.name=qixos-test -c user.email=test@qixos.invalid \
        commit -q --allow-empty -m "onto the checked-out branch"
      onto=$(git -C "$dir/clone" rev-parse HEAD)
      if ! git -C "$dir/clone" push -q origin HEAD:refs/heads/master 2>"$dir/err"; then
        echo "a push to the checked-out branch was refused with a clean worktree:" >&2
        cat "$dir/err" >&2
        exit 1
      fi
      if [ "$(git -C ${vault}/${repo} rev-parse HEAD)" != "$onto" ]; then
        echo "the vault's branch did not move to the pushed commit" >&2
        exit 1
      fi

      # And refused while it is dirty, naming the file in the way, because an edit in
      # the vault outranks an incoming push.
      echo "an edit of my own" >> ${vault}/${repo}/live.txt
      git -C "$dir/clone" -c user.name=qixos-test -c user.email=test@qixos.invalid \
        commit -q --allow-empty -m "should not land"
      if git -C "$dir/clone" push -q origin HEAD:refs/heads/master 2>"$dir/err2"; then
        echo "a push landed while the vault had uncommitted edits" >&2
        exit 1
      fi
      if ! grep -q "edits of its own" "$dir/err2"; then
        echo "the push was refused, but not by the vault's hook:" >&2
        cat "$dir/err2" >&2
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
      for service in ${readService} ${writeService}; do
        for arg in "" "../../etc" "${repo}/.." ".hidden" "no-such-repo"; do
          if QREXEC_SERVICE_ARGUMENT="$arg" "$service" </dev/null >/dev/null 2>&1; then
            echo "$service acted on the argument '$arg'" >&2
            exit 1
          fi
        done
      done

      # The fixture itself has to work, or the loop above proves nothing. upload-pack
      # advertises its refs and then fails on the empty stdin, which is 128.
      status=0
      QREXEC_SERVICE_ARGUMENT="${repo}" ${readService} </dev/null >/dev/null 2>&1 || status=$?
      if [ "$status" != 128 ] && [ "$status" != 0 ]; then
        echo "the service did not serve ${repo} either (status $status)" >&2
        exit 1
      fi
    '';

    # Reading and writing are separate grants, so the read service must refuse a push
    # even from a qube dom0 allowed to read. It runs upload-pack, which has nothing to
    # write with, and this is what would notice if it ever ran anything else.
    config-vault-read-path-cannot-write = test "config-vault-read-path-cannot-write" ''
      dir=$(mktemp -d)
      ref=refs/heads/through-the-read-path
      # Both ends, because the ref is in a repo that outlives the nube's boot: a run
      # that left one behind would otherwise fail every run after it.
      drop() { git -C ${vault}/${repo} update-ref -d "$ref" 2>/dev/null || true; }
      cleanup() { drop; rm -rf "$dir"; }
      drop
      trap cleanup EXIT
      ${viaReadServiceOnly}

      git clone -q "git+ssh://config-vault.qube/${repo}" "$dir/clone"
      git -C "$dir/clone" -c user.name=qixos-test -c user.email=test@qixos.invalid \
        commit -q --allow-empty -m "must not land"
      if git -C "$dir/clone" push -q origin "HEAD:$ref" 2>/dev/null; then
        echo "a push went through the read service" >&2
        exit 1
      fi
      if git -C ${vault}/${repo} rev-parse --verify -q "$ref" >/dev/null; then
        echo "the push was reported as failed but its ref is in the vault" >&2
        exit 1
      fi
    '';
  };
}
