{
  description = ''
    Split password entry, end to end, for trying by hand.

    A vault holding a throwaway `pass` store and the menu, and a browser to paste into.
    Not part of the suite: nothing here is asserted on, and the point is the one thing
    the automated tests cannot reach, which is dom0 deciding where a secret goes and a
    real application asking for the selection.
    '';

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    opQixCommunity = {
      url = "path:../../..";
    };

    # TODO: go back to master when appropriate
    qixCore = {
      url = "git+https://github.com/originalposter/qixos?ref=unstable";
    };
  };

  outputs = { self, nixpkgs, opQixCommunity, qixCore, ... }:
  let
    # FIXME: This should not be hard-coded - it should be provisioned somehow
    adminKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKGEbNDM5L7K4wY8CWsvY72UflD7k44Ym3C5uMy6ydBE qixos-admin-test";

    sharedModules = [ opQixCommunity.nixosModules.modules.blueprints.basic-template ];

    # ssh on both, so the demo can be inspected from the admin when something does not
    # behave. Not required by the demo itself.
    reachable = [
      opQixCommunity.nixosModules.modules.qubes-ssh-server
      {
        qubesSshServer = {
          enable = true;
          authorizedKeys = [ adminKey ];
        };
      }
    ];

    # A store planted at first boot, so the menu has something to show without anyone
    # setting up gpg by hand.
    #
    # The key has no passphrase. That keeps the demo to one prompt, dom0's, but it also
    # means gpg-agent never asks for anything, so this does not exercise the graphical
    # pinentry the blueprint switched to. Put a passphrase on a key here if that is what
    # you want to check.
    #
    # Entries are named `<service>+<username>` except the last, which is there to show
    # what `--with-username` does when an entry does not carry one.
    fixtureStore = { pkgs, ... }: {
      systemd.services.demo-password-store = {
        description = "Plant a throwaway pass store for the split password demo";
        wantedBy = [ "multi-user.target" ];
        after = [ "local-fs.target" ];

        path = with pkgs; [ gnupg pass coreutils ];

        serviceConfig = {
          Type = "oneshot";
          User = "user";
          RemainAfterExit = true;
        };

        script = ''
          set -eu

          # /home is bound from /rw, so the store outlives a reboot and this is a
          # first-boot job rather than a per-boot one.
          if [ -d "$HOME/.password-store" ]; then
            exit 0
          fi

          export GNUPGHOME="$HOME/.gnupg"
          mkdir -p "$GNUPGHOME"
          chmod 700 "$GNUPGHOME"

          gpg --batch --passphrase "" --quick-generate-key \
            "QixOS Demo <demo@example.invalid>" default default never

          pass init demo@example.invalid

          printf 'hunter2\n' | pass insert -m 'github.com+op@example.invalid'
          printf 'correct-horse-battery-staple\n' | pass insert -m 'bank.example+1234567'
          printf 'no-username-here\n' | pass insert -m 'wifi'
        '';
      };
    };

    # A key planted at first boot so the backend has something to sign with. No
    # passphrase, which keeps the demo to the one prompt it is about, the vault's
    # consent dialog. Set `pinentry` on the server module and put a passphrase on this
    # key if you want to see the second prompt as well.
    fixtureKey = { pkgs, ... }: {
      systemd.services.demo-gpg-key = {
        description = "Plant a throwaway gpg key for the split gpg demo";
        wantedBy = [ "multi-user.target" ];
        after = [ "local-fs.target" ];

        path = with pkgs; [ gnupg coreutils ];

        serviceConfig = {
          Type = "oneshot";
          User = "user";
          RemainAfterExit = true;
        };

        script = ''
          set -eu

          # ~/.gnupg is bound from /rw, so this is a first-boot job rather than a
          # per-boot one.
          if [ -d "$HOME/.gnupg" ]; then
            exit 0
          fi

          export GNUPGHOME="$HOME/.gnupg"
          mkdir -p "$GNUPGHOME"
          chmod 700 "$GNUPGHOME"

          gpg --batch --passphrase "" --quick-generate-key \
            "QixOS Split GPG Demo <gpg-demo@example.invalid>" default default never
        '';
      };
    };
  in
  {
    qixosTemplateConfigurations.demo = qixCore.lib.mkNubeTemplate { inherit nixpkgs; } {
      modules = sharedModules;
    };

    qixosAppConfigurations.vault = qixCore.lib.mkNubeApp {
      directBuild = { inherit nixpkgs; };

      modules = [
        opQixCommunity.nixosModules.modules.blueprints.password
        fixtureStore
      ] ++ reachable ++ sharedModules;
    };

    qixosAppConfigurations.browser = qixCore.lib.mkNubeApp {
      directBuild = { inherit nixpkgs; };

      modules = [
        opQixCommunity.nixosModules.modules.password-menu.receiver
        {
          qubesPasswordReceiver = {
            enable = true;
            # The demo exists to find out what real applications do, and this is the
            # only view of what the receiver was actually asked.
            debugLog = "/tmp/qixos-password-deliver.log";
          };
        }

        ({ pkgs, ... }: {
          environment.systemPackages = with pkgs; [ brave ];
          programs.firefox.enable = true;
        })

      ] ++ reachable ++ sharedModules;
    };

    # The split-gpg backend. autoAccept is left at its default, which prompts for every
    # request, so each signing from the client pops a dialog here. That dialog is the
    # thing the automated tests cannot reach and the reason this demo exists.
    qixosAppConfigurations.gpgVault = qixCore.lib.mkNubeApp {
      directBuild = { inherit nixpkgs; };

      modules = [
        opQixCommunity.nixosModules.modules.evq.packages.qubes-gpg-split.server
        { qubes.gpgSplitServer.enable = true; }
        fixtureKey

        # For looking at the keyring by hand. The qrexec services carry their own gpg
        # and do not need this one.
        ({ pkgs, ... }: { environment.systemPackages = [ pkgs.gnupg ]; })
      ] ++ reachable ++ sharedModules;
    };

    # The consuming half, standing in for qixos-dev. `gpg` here is the wrapper, so
    # signing looks ordinary and crosses to the vault.
    qixosAppConfigurations.gpgClient = qixCore.lib.mkNubeApp {
      directBuild = { inherit nixpkgs; };

      modules = [
        opQixCommunity.nixosModules.modules.evq.packages.qubes-gpg-split.client
        {
          qubes.gpgSplitClient = {
            enable = true;
            # The qube name the outer config gives the vault above.
            vaultName = "test-demo-gpg-vault";
          };
        }
      ] ++ reachable ++ sharedModules;
    };

    nixosConfigurations.template = self.qixosTemplateConfigurations.demo.nixosConfigurations.default;
    nixosConfigurations.vault = self.qixosAppConfigurations.vault.nixosConfigurations.default;
    nixosConfigurations.browser = self.qixosAppConfigurations.browser.nixosConfigurations.default;
    nixosConfigurations.gpg-vault = self.qixosAppConfigurations.gpgVault.nixosConfigurations.default;
    nixosConfigurations.gpg-client = self.qixosAppConfigurations.gpgClient.nixosConfigurations.default;
  };
}
