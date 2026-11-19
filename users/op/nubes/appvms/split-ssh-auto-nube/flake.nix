{
  description = ''
     split-ssh-auto-nube: a split-ssh vault whose keys sign without asking, for clients
     that run unattended, such as the backup repo nube
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
    qixosAppConfigurations.split-ssh-auto-nube = qixCore.lib.mkNubeApp {
      modules = [
        # Every key here signs for whoever dom0 policy lets call qubes.SshAgent on this
        # nube, without asking, so keep only keys meant for that here, and the policy to
        # the nubes that need them.
        opQixCommunity.nixosModules.modules.qubes-split-ssh-server
        {
          qubesSplitSshServer = {
            enable = true;
            keyDirs = [ ];
            autoKeyDirs = [ "/home/user/.ssh/keys" ];
          };
        }
      ] ++ [ opQixCommunity.nixosModules.modules.blueprints.basic-template ];
    };
  };
}
