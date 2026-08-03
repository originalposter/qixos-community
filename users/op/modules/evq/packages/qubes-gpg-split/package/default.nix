{
  fetchFromGitHub,
  resholve,
  coreutils,
  qubes-core-qrexec,
  qubes-core-agent-linux,
  gnupg,
  libnotify,
  pandoc,
  zenity,
}:
resholve.mkDerivation rec {
  pname = "qubes-gpg-split";
  version = "2.0.77";

  src = fetchFromGitHub {
    owner = "QubesOS";
    repo = "qubes-app-linux-split-gpg";
    rev = "v${version}";
    hash = "sha256-AGYJV+moLh58dbKi9K2aguPNHYE4ntQ8OmZvADAec0s=";
  };

  postPatch = ''
    substituteInPlace src/gpg-client.c --replace \
      '#define QREXEC_CLIENT_PATH "/usr/lib/qubes/qrexec-client-vm"' \
      '#define QREXEC_CLIENT_PATH "${qubes-core-qrexec}/bin/qrexec-client-vm"'

    # Here gpg2 is an *argument* to gpg-server, not a command word, so
    # resholve's `fix` will not touch it -- and the `cannot:` verdict on
    # gpg-server stops it walking in to resolve arguments either. Left alone
    # it stays /usr/bin/gpg2 and the backend dies on first use.
    substituteInPlace qubes.Gpg.service --replace \
      '/usr/bin/gpg2' '${gnupg}/bin/gpg2'
  '';

  buildInputs = [
    qubes-core-qrexec
    gnupg
  ];

  nativeBuildInputs = [
    pandoc
  ];

  buildPhase = ''
    make
  '';

  installPhase = ''
    make install-vm \
        DESTDIR="$out" \
        LIBDIR=/lib \
        USRLIBDIR=/lib \
        SYSLIBDIR=/lib

    mv $out/usr/bin $out/bin
    mv $out/usr/share $out/share
    # The Makefile hardcodes /usr/lib for the tmpfiles snippet rather than
    # honouring LIBDIR, so it lands outside $out/lib and would be lost to the
    # rm below. The backend needs it to get /run/qubes-gpg-split created.
    mv $out/usr/lib/tmpfiles.d $out/lib/tmpfiles.d
    rm -rf $out/usr
  '';

  solutions = {
    default = {
      scripts = [
        "bin/qubes-gpg-client-wrapper"
        "bin/qubes-gpg-import-key"
        "etc/profile.d/qubes-gpg.sh"
      ];
      interpreter = "none";
      fix = {
        source = ["/etc/profile.d/qubes-gpg.sh"];
        "/usr/bin/gpg" = true;
        "/usr/lib/qubes/qrexec-client-vm" = true;
      };
      inputs = [
        "bin"
        "etc/profile.d"
        coreutils
        gnupg
        qubes-core-qrexec
      ];
      execer = [
        "cannot:bin/qubes-gpg-client"
        "cannot:bin/qubes-gpg-import-key"
        "cannot:${gnupg}/bin/gpg"
        # FIXME this is a lie
        # NOTE the invocation in qubes-gpg-import-key passes absolute paths
        "cannot:${qubes-core-qrexec}/bin/qrexec-client-vm"
      ];
    };

    # The qrexec services run in the backend (key-holding) qube. Upstream ships
    # them with FHS paths baked in, so they are resolved here rather than
    # reimplemented, to avoid drifting from upstream's consent/notify logic.
    backend = {
      scripts = [
        "etc/qubes-rpc/qubes.Gpg"
        "etc/qubes-rpc/qubes.GpgImportKey"
      ];
      interpreter = "none";
      fix = {
        "/usr/bin/gpg2" = true;
        "/usr/lib/qubes-gpg-split/gpg-server" = true;
        "/etc/qubes-rpc/qubes.WaitForSession" = true;
      };
      inputs = [
        "lib/qubes-gpg-split"
        "${qubes-core-agent-linux}/etc/qubes-rpc"
        coreutils
        gnupg
        libnotify
        zenity
      ];
      execer = [
        # gpg-server execs the gpg binary named in its own argv, which
        # postPatch has already pinned to a store path. The calling qube
        # cannot influence it.
        "cannot:lib/qubes-gpg-split/gpg-server"

        # gpg2 genuinely does exec (gpg-agent, pinentry, keyserver helpers,
        # --photo-viewer, --exec-path), so binlore is right to flag it. The
        # narrower claim made here is that the *calling qube* cannot steer any
        # of those execs: gpg-server re-parses the client's argv against the
        # static allowlist in src/gpg-common.h and rejects anything else.
        # --photo-viewer, --exec-path and --keyserver* are not in its option
        # table at all, so getopt_long returns '?' and it exits; --command-fd
        # and --use-agent parse but are absent from gpg_allowed_options and
        # are refused as "Forbidden option".
        #
        # Consequence of stopping resholve's walk here: whatever gpg2 execs at
        # runtime is NOT in this package's closure. gpg-agent ships inside
        # gnupg itself, so it is covered. pinentry is not, and is only reached
        # if a backend key carries a passphrase -- which cannot work under
        # qrexec anyway, since the service has no terminal and the client
        # strips the --ttyname/--display options that would redirect the
        # prompt. Such a key fails with "Inappropriate ioctl for device".
        "cannot:${gnupg}/bin/gpg2"

        "cannot:${qubes-core-agent-linux}/etc/qubes-rpc/qubes.WaitForSession"

        # binlore rates zenity "might exec", but the only call here is a
        # --question dialog whose text is rendered, never run.
        "cannot:${zenity}/bin/zenity"
      ];
    };
  };
}
