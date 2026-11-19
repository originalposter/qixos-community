{
  description = ''
    backup-repo-nube: holds other nubes' restic repositories. See modules/backup/repo.nix.
  '';

  inputs = {
    opQixCommunity = {
      url = "path:../../../";
    };

    qixCore = {
      url = "git+https://github.com/originalposter/qixos?ref=refs/tags/v0.2.0";
    };
  };

  outputs = { self, opQixCommunity, qixCore, ... }:
  {
    qixosAppConfigurations.default = qixCore.lib.mkNubeApp {
      modules = [
        # Backups run unattended, so the ssh key that reaches a storage server is in a
        # vault of its own whose keys sign without asking, split-ssh-auto-nube, and only
        # the backup service is pointed at it; ssh by hand here keeps asking the usual
        # vault. dom0 policy, so that only this nube can use that vault:
        #
        #   qubes.SshAgent * backup-repo-nube split-ssh-auto-nube allow
        opQixCommunity.nixosModules.modules.qubes-split-ssh-client
        ({ lib, ... }: {
          qubesSplitSsh = {
            enable = true;
            vault = lib.mkDefault "split-ssh-nube";
            extraVaults = lib.mkDefault [ "split-ssh-auto-nube" ];
          };
          qixosBackupRepo.storage.sshAgent = "/run/split-ssh/split-ssh-auto-nube.sock";
        })

        # dom0 policy, in a file under /etc/qubes/policy.d/, for the nubes that back up:
        #
        #   qixos.ResticBackup * @tag:created-by-qixos-admin backup-repo-nube allow
        #
        # The repositories go in ~/qixos-backup-repos here. To keep them on a server
        # instead, set qixosBackupRepo.storage; see the module's header.
        opQixCommunity.nixosModules.modules.backup.repo
        { qixosBackupRepo.enable = true; }

        opQixCommunity.nixosModules.modules.blueprints.basic-template
      ];
    };
  };
}
