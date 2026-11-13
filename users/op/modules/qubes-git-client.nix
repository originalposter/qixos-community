# Client half of fetching git from another qube. Teaches git that a host ending in
# `.qube` is reached over qrexec, so `git+ssh://<qube>.qube/<repo>` fetches from the
# config vault that blueprints/config-vault runs there.
#
#   git clone git+ssh://config-vault-nube.qube/qixos-community
#   git push  git+ssh://config-vault-nube.qube/qixos-community master
#   remoteFlake.url = "git+ssh://config-vault-nube.qube/qixos-community?ref=master&dir=...";
#   remoteFlake.url = "git+ssh://config-vault-nube.qube/qixos-community?ref=refs/qixos/live&dir=...";
#
# No key and no secret: for a `.qube` host the wrapper does not run ssh at all, it runs
# qrexec-client-vm, and dom0 policy is the whole of the authorisation.
#
# Pulling needs dom0 policy, in a file under /etc/qubes/policy.d/.
#
# The realm reads the vault, and whoever edits it writes, each line naming the
# repository it is about:
#
#   qixos.ReadConfigVault  +qixos-community @tag:created-by-qixos-admin config-vault-nube allow
#   qixos.WriteConfigVault +qixos-community review-nube                 config-vault-nube ask
#
# `*` in place of `+qixos-community` covers every repository in the vault. `ask` on the
# write line makes dom0 prompt for each push, which is worth having where `allow` would
# let anything running in that qube rewrite a config silently.
#
# System git config, so it also applies to root fetching nube configs in a template
# during qixos.Switch.
{ pkgs, ... }:
let
  wrapper = pkgs.writeShellApplication {
    name = "qubes-git-ssh";
    runtimeInputs = [ pkgs.qubes-core-qrexec pkgs.openssh pkgs.coreutils ];
    text = ''
      # git invokes this the way it invokes ssh: options, then the host, then the
      # command. Kept whole, because everything that is not a vault is handed to real
      # ssh exactly as git meant it.
      args=("$@")

      # A probe carries -G and no command. Real ssh answers it without connecting, which
      # is how git works out it is talking to OpenSSH.
      for arg in "$@"; do
        if [ "$arg" = -G ]; then exec ssh "''${args[@]}"; fi
      done

      # git passes the remote command as one argument, last, with the host just before
      # it, whatever options it puts in front.
      if [ "''${#args[@]}" -lt 2 ]; then exec ssh "''${args[@]}"; fi
      host=''${args[-2]}
      command=''${args[-1]}

      case $host in
        *.qube) ;;
        # A real host, the forge and github included, so the real ssh runs and takes its
        # port and its ProxyCommand from git and ssh_config as usual.
        *) exec ssh "''${args[@]}" ;;
      esac

      case $command in
        "git-upload-pack "*) service=qixos.ReadConfigVault; path=''${command#git-upload-pack } ;;
        "git-receive-pack "*) service=qixos.WriteConfigVault; path=''${command#git-receive-pack } ;;
        # Anything else is not git talking to a vault, so it is not this wrapper's
        # business.
        *) exec ssh "''${args[@]}" ;;
      esac

      path=''${path#\'}
      path=''${path%\'}
      repo=$(basename "$path" .git)
      exec qrexec-client-vm "''${host%.qube}" "$service+$repo"
    '';
  };
in
{
  # See qubes-ssh-server.nix: a key of its own, so importing this by path and through
  # the flake's nixosModules cannot collide over programs.git.
  key = "qixos-community/modules/qubes-git-client";

  programs.git = {
    enable = true;
    config = {
      core.sshCommand = "${wrapper}/bin/qubes-git-ssh";
    };
  };
}
