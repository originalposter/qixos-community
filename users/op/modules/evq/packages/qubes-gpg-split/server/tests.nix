# Tests for the split-gpg backend, in default.nix which imports this file. Declared only
# when the backend is enabled, so a nube that imports the module and leaves it off does
# not advertise tests that could not pass, and installed only when qixosTests.enable is
# on.
#
# In-nube, with the qrexec hop stood in for. `gpg-client` takes QREXEC_CLIENT_PATH from
# the environment (src/gpg-client.c) and execs it as `<path> <domain> qubes.Gpg`, with
# the request already on stdin and the reply on stdout. Pointing it at a script that
# execs this qube's own qubes.Gpg therefore exercises the real client, the real wire
# format, the real service and the real gpg-server, with only the transport replaced.
# Same trade the password-menu tests make, and for the same reason: a second qube buys
# only the transport, and costs a build and a policy line.
#
# They keep to a temporary GNUPGHOME and clean up on the way out, so a nube whose
# keyring is real can run them.
{ pkgs, lib, config, ... }:
let
  cfg = config.qubes.gpgSplitServer;

  # The domain the stand-in claims to be calling from. A name no real qube has, so the
  # consent it is granted below cannot be mistaken for a client's, and a stat file that
  # outlived its cleanup would grant nothing to anyone.
  fakeClient = "gpg-split-self-test";

  servicePath = "/etc/qubes-rpc/qubes.Gpg";

  # Stands in for qrexec-client-vm. Its two arguments are the domain and the service
  # name, both of which it ignores: the service is in this qube, and which one it is was
  # decided when this was written rather than by the caller.
  #
  # /etc/qubes-rpc rather than cfg.package's own etc/qubes-rpc, since that is where core
  # merges the service packages and the only directory the agent searches. Reaching into
  # the store path would call a file qrexec never reaches for, and would pass even if
  # this module had failed to register the service at all.
  transport = pkgs.writeShellApplication {
    name = "qixos-gpg-split-loopback";
    text = ''
      QREXEC_REMOTE_DOMAIN=${fakeClient} exec ${servicePath}
    '';
  };

  # A keyring of its own, so that a nube someone actually keeps keys in can run these.
  # GNUPGHOME reaches the backend because nothing between here and gpg2 scrubs the
  # environment: the wrapper, the client, the stand-in transport, qubes.Gpg and
  # gpg-server all inherit it, which is the same path the request itself takes.
  #
  # The key is generated rather than committed, a fixture key in the repo being a
  # private key in the repo. No passphrase, since `pinentry` is not necessarily set on
  # the nube running these and an agent without one cannot prompt.
  #
  # Consent is granted by touching the file qubes.Gpg checks, because nothing here can
  # answer its zenity dialog. That dialog is the one part of the backend these walk
  # around, and the part no test can cover: whether it renders and can be clicked is a
  # question for a person.
  #
  # The trap runs on the way out however that happens, so a test that fails partway
  # leaves no more behind than one that passes.
  sandbox = ''
    uid="qixos-split-gpg-test@example.invalid"

    GNUPGHOME=$(mktemp -d)
    export GNUPGHOME

    cleanup() {
      # Started by gpg in the temporary home and holding it open until told otherwise.
      gpgconf --kill all >/dev/null 2>&1 || true
      rm -rf "$GNUPGHOME"
      rm -f "/run/qubes-gpg-split/stat.${fakeClient}"
    }
    trap cleanup EXIT

    mkdir -p /run/qubes-gpg-split
    touch "/run/qubes-gpg-split/stat.${fakeClient}"

    gpg --batch --passphrase "" --quick-generate-key "$uid" default default never
  '';

  mkTest = name: text: pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = [ cfg.package transport pkgs.coreutils pkgs.gnupg ];
    text = ''
      export QUBES_GPG_DOMAIN=${fakeClient}
      export QREXEC_CLIENT_PATH=${transport}/bin/qixos-gpg-split-loopback
    '' + text;
  };
in
{
  config = lib.mkIf cfg.enable {
    qixosTests.tests = {

      # Cheapest of these and the first to look at when the others fail: if the service
      # is not in /etc/qubes-rpc then nothing below could have worked anyway, and the
      # fault is the module's wiring rather than anything about gpg.
      gpg-split-service-registered =
        mkTest "gpg-split-service-registered" ''
          if [ ! -x ${servicePath} ]; then
            echo "qubes.Gpg is not in /etc/qubes-rpc" >&2
            exit 1
          fi
          echo "registered at ${servicePath}"
        '';

      # The whole path in one: the wrapper's argument handling, the client binary, the
      # service script as resholve left it, gpg-server, and the gpg2 pinned into the
      # service by postPatch. Any of those being wrong shows up here.
      gpg-split-client-signs-through-the-backend =
        mkTest "gpg-split-client-signs-through-the-backend" ''
          ${sandbox}

          signed=$(echo "qixos split gpg sentinel" |
            qubes-gpg-client-wrapper --clearsign --local-user "$uid")

          case "$signed" in
            *"BEGIN PGP SIGNED MESSAGE"*"BEGIN PGP SIGNATURE"*) ;;
            *) echo "no signature came back:" >&2; echo "$signed" >&2; exit 1 ;;
          esac

          # Signed by the backend's key rather than merely wrapped in the right text,
          # which a client-side gpg falling back to its own keyring would also produce.
          echo "$signed" | gpg --verify 2>&1 | grep -q "$uid" || {
            echo "the signature does not verify against $uid" >&2
            exit 1
          }

          echo "signed through the backend and verified"
        '';

      # gpg-server re-parses the client's argv against the allowlist in
      # src/gpg-common.h, which is what stops a client asking for the key itself rather
      # than for its use. The clearsign test above says the path works; this says the
      # path is narrow.
      gpg-split-refuses-to-export-the-secret-key =
        mkTest "gpg-split-refuses-to-export-the-secret-key" ''
          ${sandbox}

          if exported=$(qubes-gpg-client-wrapper --export-secret-keys "$uid" 2>&1); then
            echo "the backend served a secret key export" >&2
            echo "$exported" >&2
            exit 1
          fi

          case "$exported" in
            *"PRIVATE KEY BLOCK"*)
              echo "the export was refused but private key material came back anyway" >&2
              exit 1
              ;;
          esac

          echo "secret key export refused"
        '';
    };
  };
}
