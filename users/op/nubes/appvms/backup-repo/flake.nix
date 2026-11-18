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
        opQixCommunity.nixosModules.modules.qubes-split-ssh-client
        ({ lib, ... }: { qubesSplitSsh = { enable = true; vaultName = lib.mkDefault "split-ssh-nube"; }; })

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
