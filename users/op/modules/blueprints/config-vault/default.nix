# A config vault: a nube serving git repos to other nubes, so a nube config can live on
# this machine instead of on a forge, and can be edited here rather than in the admin.
#
# Two ways in, deliberately unequal.
#
# - Push over the qixos.WriteConfigVault qrexec service, which takes the repository as
#   its service argument and runs receive-pack on that one repository. There is no sshd
#   and no key on this nube: the calling qube is the principal, and the dom0 line is the
#   whole of the authority, so what it grants is readable in the policy file
#   rather than enforced out of sight inside the vault. Use `ask` rather than `allow` for
#   a prompt on every push, which dom0 asks and nothing in the calling qube can skip.
# - Pull over the qixos.ReadConfigVault qrexec service, which takes the repository as its
#   service argument and runs upload-pack on that one repository. No credentials, because
#   a template has to fetch without holding a secret. Nothing the client sends decides
#   which repository is served, so dom0 policy decides it: a line per repository, or `*`
#   for all of them. qubes-git-client.nix is the other half and documents the policy.
#
# The vault is more trusted than the qubes that pull from it and than the one that
# pushes to it, and both halves above are what hold that order up. A pusher reaches only
# receive-pack and runs nothing here. A puller gets upload-pack on one repository, which
# is reading, with one exception worth knowing: serving a repo that has a worktree
# refreshes refs/qixos/live, so a fetch does make the vault write objects and move that
# ref, though never to anything the puller chose.
#
# Two things follow. Nothing private goes in the directory that is not meant for every
# qube allowed to read it, because reading is where a more trusted vault can still lose.
# And this nube's own configuration must not come from the vault, or the order inverts,
# since whoever pushes would then decide what the vault itself runs.
#
# The repos are made by hand, and this module makes none, so no repo name appears in it:
#
#   git init ~/config-vault/qixos-community        # a worktree to edit in
#   git init --bare ~/config-vault/other.git       # or bare, if nobody edits here
#
# TODO: have `setup` do this, once halp and setup is finished.
#
# A repo with a worktree is the point of the vault: someone edits the files in place,
# with no git knowledge needed, and `refs/qixos/live` carries whatever is on disk,
# snapshotted at fetch time, so a template can build an edit nobody committed. A repo
# served from the vault can still be bare, and then only its committed refs exist.
{ pkgs, lib, config, ... }:
let
  cfg = config.configVault;
  user = config.services.qubes.core.username;
  dir = "/home/${user}/${cfg.directory}";

  readName = "qixos.ReadConfigVault";
  writeName = "qixos.WriteConfigVault";

  # Anything a client chooses reaches these two scripts, so both validate before acting.

  # The read side. The repository is the qrexec argument, and nothing else is taken from
  # the caller, which is the point: a client cannot ask for a path, only for a name.
  #
  # That name is still the client's. dom0 matches it against a rule, but a rule may be
  # `*`, and qrexec hands the argument over without inspecting it, so the shape check
  # below is what stands between a name and the rest of the filesystem.
  #
  # It runs as the account that owns the repos, with no containment, which is the one
  # place this blueprint trades safety for simplicity: a bug in upload-pack reaches the
  # whole home rather than one directory. Wrapping the exec is a line and a dependency
  # when that trade stops looking good:
  #
  #   exec ${"\${pkgs.bubblewrap}"}/bin/bwrap \
  #     --ro-bind /nix/store /nix/store --ro-bind ${dir} ${dir} \
  #     --proc /proc --dev /dev --unshare-all --die-with-parent \
  #     ${"\${pkgs.git}"}/bin/git upload-pack --strict "$gitdir"
  #
  # Checked: a fetch through that works and costs nothing measurable, and the binary has
  # to be the store path, since the one on PATH is a profile symlink the sandbox has no
  # reason to carry. systemd-run --user --pipe with the usual hardening works too, and is
  # the same length, but needs the user's bus and so fails before anyone has logged in.
  readService = pkgs.writeShellApplication {
    name = readName;
    runtimeInputs = [ pkgs.git pkgs.coreutils ];
    text = ''
      repo=''${QREXEC_SERVICE_ARGUMENT:-}

      # No slashes, no dots leading anywhere, nothing to escape ${dir} with.
      case $repo in
        "" | *[!a-zA-Z0-9._-]* | .* | *..*)
          echo "not a repository name: $repo" >&2
          exit 1
          ;;
      esac

      if [ -d "${dir}/$repo/.git" ]; then
        gitdir=${dir}/$repo/.git
        # The live ref: whatever is in the worktree, as a commit, without touching the
        # index or what `git status` says. Built from a copy of the index so an edit in
        # progress is included and the person editing sees nothing change.
        # A copy of their index, so `add -A` below records into that and leaves the
        # index the person is using alone. Removed again when there is nothing to copy,
        # because git rejects an empty index file but is happy to create a missing one,
        # and a repo with no commit yet has no index.
        index=$(mktemp)
        if ! cp "$gitdir/index" "$index" 2>/dev/null; then
          rm -f "$index"
        fi
        if GIT_INDEX_FILE=$index git -C "${dir}/$repo" add -A 2>/dev/null; then
          tree=$(GIT_INDEX_FILE=$index git -C "${dir}/$repo" write-tree)
          # --verify -q, because plain `rev-parse HEAD` prints the string "HEAD" on
          # stdout when it cannot resolve it, and a repo with no commit yet would hand
          # that back as though it were a sha.
          head=$(git --git-dir="$gitdir" rev-parse --verify -q HEAD || true)

          if [ -n "$head" ] && [ "$tree" = "$(git --git-dir="$gitdir" rev-parse --verify -q "HEAD^{tree}")" ]; then
            # Nothing uncommitted, so the live ref is just the commit, and no object is
            # made at all.
            git --git-dir="$gitdir" update-ref refs/qixos/live "$head"
          else
            # Fixed dates, so one working tree is one commit however often it is
            # fetched. A commit records when it was made, so taking the clock here would
            # mint a new sha on every fetch, which a puller reads as a change: its lock
            # would move and its rev would stop meaning anything. With the dates pinned,
            # the sha is a function of the content and the parent, and a fetch that
            # changes nothing changes nothing.
            #
            # A repo with no commit yet gets a snapshot with no parent, since someone
            # who has not learned to commit is exactly who this is for.
            set -- commit-tree "$tree" -m "live tree"
            if [ -n "$head" ]; then set -- "$@" -p "$head"; fi
            live=$(GIT_AUTHOR_DATE="@0 +0000" GIT_COMMITTER_DATE="@0 +0000" \
              git --git-dir="$gitdir" -c user.name=config-vault \
              -c user.email=config-vault@invalid "$@")
            git --git-dir="$gitdir" update-ref refs/qixos/live "$live"
          fi
        fi
        rm -f "$index"
      elif [ -d "${dir}/$repo.git" ]; then
        gitdir=${dir}/$repo.git
      else
        echo "no such repository: $repo" >&2
        exit 1
      fi

      # The name cannot escape ${dir}, but a symlink planted directly under it could,
      # and only the vault's own account can plant one. Checked anyway, because the
      # forced command this replaced checked it and nothing else does now.
      case $(realpath "$gitdir") in
        ${dir}/*) ;;
        *) echo "refusing a repository outside ${dir}" >&2; exit 1 ;;
      esac

      exec git upload-pack --strict "$gitdir"
    '';
  };

  # Writing. The same argument check as reading, because the same thing is being
  # trusted: a name the caller chose. receive-pack rather than upload-pack is the only
  # difference, and no live ref to refresh, since the read side recomputes that from the
  # worktree every time it serves.
  writeService = pkgs.writeShellApplication {
    name = writeName;
    runtimeInputs = [ pkgs.git pkgs.coreutils ];
    text = ''
      repo=''${QREXEC_SERVICE_ARGUMENT:-}

      case $repo in
        "" | *[!a-zA-Z0-9._-]* | .* | *..*)
          echo "not a repository name: $repo" >&2
          exit 1
          ;;
      esac

      if [ -d "${dir}/$repo/.git" ]; then
        gitdir=${dir}/$repo/.git
      elif [ -d "${dir}/$repo.git" ]; then
        gitdir=${dir}/$repo.git
      else
        echo "no such repository: $repo" >&2
        exit 1
      fi

      # The name cannot escape ${dir}, but a symlink planted directly under it could,
      # and only the vault's own account can plant one. Checked anyway, because the
      # forced command this replaced checked it and nothing else does now.
      case $(realpath "$gitdir") in
        ${dir}/*) ;;
        *) echo "refusing a repository outside ${dir}" >&2; exit 1 ;;
      esac

      exec git receive-pack "$gitdir"
    '';
  };

  # qrexec runs a service as `user` unless the dom0 line says otherwise, which is the
  # account owning the repos, so the default is already right. Pinned anyway: a policy
  # line carrying `user=root` would have either service writing root-owned objects into
  # someone's home, which is too quiet a way to break a vault for a default to be all
  # that stands in the way.
  rpcConfig = pkgs.writeText "config-vault-rpc-config" ''
    force-user = '${user}'
  '';

  vaultServices = pkgs.runCommand "config-vault-services" { } ''
    mkdir -p $out/etc/qubes-rpc $out/etc/qubes/rpc-config
    cp ${readService}/bin/${readName} $out/etc/qubes-rpc/${readName}
    cp ${writeService}/bin/${writeName} $out/etc/qubes-rpc/${writeName}
    cp ${rpcConfig} $out/etc/qubes/rpc-config/${readName}
    cp ${rpcConfig} $out/etc/qubes/rpc-config/${writeName}
  '';

  # Runs instead of what `updateInstead` would do, with the pushed commit in $1, so the
  # pusher is told which files are in the way rather than just that something is. It
  # declines rather than parking the work: the vault is where the editing happens, so an
  # edit here outranks an incoming push.
  #
  # The working directory is the git dir when a hook runs, which is why the worktree and
  # the index are named rather than assumed.
  pushToCheckout = pkgs.writeShellApplication {
    name = "push-to-checkout";
    runtimeInputs = [ pkgs.git pkgs.coreutils ];
    text = ''
      cd "$GIT_WORK_TREE"

      if ! git diff-index --quiet HEAD -- \
        || [ -n "$(git ls-files --others --exclude-standard)" ]; then
        echo "the config vault has edits of its own, which this push would overwrite:" >&2
        git status --short >&2
        echo "commit or discard them in the vault, then push again." >&2
        exit 1
      fi

      git read-tree -u --reset "$1"
    '';
  };

  hooks = pkgs.runCommand "config-vault-hooks" { } ''
    mkdir -p $out
    cp ${pushToCheckout}/bin/push-to-checkout $out/push-to-checkout
  '';
in
{
  # The runner declares the option the tests assign to, and cannot be reached across a
  # flake boundary, so it comes along by relative path the way qix-pw/receiver.nix does.
  #
  imports = [
    ../../../tests/runner.nix
    ./tests.nix
  ];

  options.configVault = {
    directory = lib.mkOption {
      type = lib.types.str;
      default = "config-vault";
      description = ''
        Directory under the account's home holding the vault's repositories. Both
        halves are scoped to it: each takes a repository name rather than a path, and
        resolves it inside this directory or refuses.
      '';
    };

  };

  config = {
    # For reading a repo by hand, and because the admin test runs `git ls-remote` on the
    # vault over ssh. Serving does not depend on it: both scripts name their own git.
    environment.systemPackages = [ pkgs.git ];

    services.qubes.qrexec.packages = [ vaultServices ];

    # In the system config because this module creates no repos and so has nowhere else
    # to put it. Every repo on the vault gets it, which is what a vault is for, and the
    # cost of `hooksPath` is that a repo here cannot carry hooks of its own.
    programs.git = {
      enable = true;
      config = {
        receive.denyCurrentBranch = "updateInstead";

        # The pusher is less trusted than the vault, and receive-pack stores whatever
        # objects it is handed, so check them here rather than finding out later on a
        # template that fetched them.
        receive.fsckObjects = true;

        core.hooksPath = "${hooks}";
      };
    };

    # The directory, not the repos in it. A unit rather than tmpfiles, which runs before
    # qubes-mount-dirs has put /home in place and would write to the root volume an AppVM
    # throws away.
    systemd.services.config-vault-dir = {
      description = "Create the config vault's directory under /home";
      after = [ "qubes-mount-dirs.service" ];
      requires = [ "qubes-mount-dirs.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = user;
        ExecStart = "${pkgs.coreutils}/bin/mkdir -p ${dir}";
      };
    };
  };
}
