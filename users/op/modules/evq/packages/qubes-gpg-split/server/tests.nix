# Tests for the split-gpg backend, imported by default.nix. They declare nothing unless
# the backend is enabled and install nothing unless qixosTests.enable is on.
#
# The qrexec hop is stood in for rather than made. gpg-client execs whatever
# QREXEC_CLIENT_PATH names, as `<path> <domain> qubes.Gpg` with the request already on
# stdin (src/gpg-client.c), so a script that execs this qube's own qubes.Gpg leaves the
# client, the service and gpg-server real and replaces only the transport. A second qube
# would buy that transport, and cost a build and a dom0 rule.
{ pkgs, lib, config, ... }:
let
  cfg = config.qubes.gpgSplitServer;

  # The domain the stand-in claims to call from. No real qube has this name, so a stamp
  # that outlives its cleanup grants nothing to anyone.
  fakeClient = "gpg-split-self-test";

  servicePath = "/etc/qubes-rpc/qubes.Gpg";

  # Stands in for qrexec-client-vm, ignoring the domain and service name it is passed.
  # Calls /etc/qubes-rpc rather than cfg.package's own copy, because that is the
  # directory the agent searches, so a module that failed to register its service fails
  # here too.
  transport = pkgs.writeShellApplication {
    name = "qixos-gpg-split-loopback";
    text = ''
      QREXEC_REMOTE_DOMAIN=${fakeClient} exec ${servicePath}
    '';
  };

  # A keyring of its own, so a nube holding real keys can run these. GNUPGHOME reaches
  # the backend because nothing from the wrapper down to gpg2 scrubs the environment.
  # The key is generated rather than committed, and passphraseless because `pinentry`
  # may be unset and an agent without one cannot prompt.
  #
  # Consent is forged rather than given. qubes.Gpg serves a request when
  # `stamp + autoAccept < now` is false, so a stamp in the future satisfies any window
  # and these run under whatever autoAccept the nube is configured with. Whether the
  # dialog that skips renders and can be clicked is a question for a person, and the one
  # thing here no test covers.
  sandbox = ''
    uid="qixos-split-gpg-test@example.invalid"

    GNUPGHOME=$(mktemp -d)
    export GNUPGHOME

    cleanup() {
      # gpg starts one in the temporary home, and it holds the directory open.
      gpgconf --kill all >/dev/null 2>&1 || true
      rm -rf "$GNUPGHOME"
      rm -f "/run/qubes-gpg-split/stat.${fakeClient}"
    }
    trap cleanup EXIT

    mkdir -p /run/qubes-gpg-split
    touch -d '+1 hour' "/run/qubes-gpg-split/stat.${fakeClient}"

    gpg --batch --passphrase "" --quick-generate-key "$uid" default default never
  '';

  # One stamped request under the window given as $1, returning its exit status so a
  # caller can assert either way round.
  stampedRequest = ''
    stamped_request() {
      touch "/run/qubes-gpg-split/stat.${fakeClient}"
      echo "qixos consent probe" |
        QUBES_GPG_AUTOACCEPT="$1" timeout 30 \
          qubes-gpg-client-wrapper --clearsign --local-user "$uid" >/dev/null 2>&1
    }
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

      # Cheapest, and the first to read when the others fail: without this nothing below
      # could have worked, and the fault is registration rather than gpg.
      gpg-split-service-registered =
        mkTest "gpg-split-service-registered" ''
          if [ ! -x ${servicePath} ]; then
            echo "qubes.Gpg is not in /etc/qubes-rpc" >&2
            exit 1
          fi
          echo "registered at ${servicePath}"
        '';

      # The whole path at once: the wrapper's argument handling, the client, the service
      # as resholve left it, gpg-server, and the gpg2 postPatch pinned into the service.
      gpg-split-client-signs-through-the-backend =
        mkTest "gpg-split-client-signs-through-the-backend" ''
          ${sandbox}

          signed=$(echo "qixos split gpg sentinel" |
            qubes-gpg-client-wrapper --clearsign --local-user "$uid")

          case "$signed" in
            *"BEGIN PGP SIGNED MESSAGE"*"BEGIN PGP SIGNATURE"*) ;;
            *) echo "no signature came back:" >&2; echo "$signed" >&2; exit 1 ;;
          esac

          # Signed by the backend's key, which a client-side gpg falling back to its own
          # keyring would not be.
          echo "$signed" | gpg --verify 2>&1 | grep -q "$uid" || {
            echo "the signature does not verify against $uid" >&2
            exit 1
          }

          echo "signed through the backend and verified"
        '';

      # gpg-server re-parses the client's argv against the allowlist in
      # src/gpg-common.h. The test above says the path works; this says it is narrow.
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

    }
    # Nothing to hold it to when the variable is left unset.
    // lib.optionalAttrs (cfg.autoAccept != null) {

      # environment.variables reaches the service through the login shell qrexec-agent
      # execs it under, and fails open: if it stops arriving, qubes.Gpg uses its own
      # 300. The consent test cannot see this, since it supplies the value itself.
      #
      # `bash -lc` stands in for that shell. Reaching the real one needs a qrexec call,
      # and so a second qube.
      gpg-split-autoaccept-reaches-the-service =
        mkTest "gpg-split-autoaccept-reaches-the-service" ''
          arrived=$(bash -lc 'echo "$QUBES_GPG_AUTOACCEPT"')
          if [ "$arrived" != "${toString cfg.autoAccept}" ]; then
            echo "a login shell sees '$arrived', the config says '${toString cfg.autoAccept}'" >&2
            exit 1
          fi
          echo "login shells see QUBES_GPG_AUTOACCEPT=$arrived"
        '';

    }
    # Only a negative window makes a stamp worthless. A positive one was opened on
    # purpose, and this would be asserting against that choice.
    // lib.optionalAttrs (cfg.autoAccept != null && cfg.autoAccept < 0) {

      # A fresh stamp is what an approval leaves behind, and under a negative window it
      # buys nothing, so one approval covers one operation.
      #
      # The 300 call is the control: same request, same stamp, only the window differs,
      # which is what makes the refusal attributable to the consent gate rather than to
      # anything else that could fail. It also catches upstream starting to validate the
      # variable and falling back to 300, which would reopen the window silently.
      gpg-split-consent-is-not-reusable =
        mkTest "gpg-split-consent-is-not-reusable" ''
          ${sandbox}
          ${stampedRequest}

          if ! stamped_request 300; then
            echo "a stamped request was refused even with a 300s window, so this says" >&2
            echo "nothing about consent. Look at the other tests first." >&2
            exit 1
          fi

          if stamped_request ${toString cfg.autoAccept}; then
            echo "a stamped request was served under autoAccept=${toString cfg.autoAccept}," >&2
            echo "so the stamp is being honoured and one approval covers more than one" >&2
            echo "operation" >&2
            exit 1
          fi

          echo "a fresh stamp buys nothing under autoAccept=${toString cfg.autoAccept}"
        '';
    };
  };
}
