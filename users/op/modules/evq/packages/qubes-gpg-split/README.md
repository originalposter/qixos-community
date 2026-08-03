# Split GPG for nubes

Private keys live in one network-isolated qube (the **backend**). Other qubes
(**clients**) ask it to sign and decrypt over qrexec, and never see the key.
The backend shows a consent dialog and a tray notification on every request.

This directory has three parts:

| Path | What it is |
|---|---|
| `package/` | upstream `qubes-app-linux-split-gpg`, resholved for NixOS |
| `server/` | `qubes.gpgSplitServer` -- the module for the key-holding qube |
| `module/` | `qubes.gpgSplitClient` -- the module for consuming qubes |

## The backend qube

`nubes/appvms/pgp-nube` is set up as one. It must have `netvm = "none"` in the
outer config -- that isolation is the entire point, and nothing in the module
enforces it.

```nix
{
  qubes.gpgSplitServer.enable = true;
}
```

The module installs no `gpg` of its own -- the qrexec services carry a pinned
one internally, so add `gnupg` to the qube's `systemPackages` if you want to
manage the keyring by hand. `pgp-nube` does.

Import or generate keys inside that qube with ordinary `gpg`. The private key
must **not** have a passphrase. This is not a policy choice: `qubes.Gpg` runs
under qrexec with no controlling terminal, and the client strips the
`--ttyname` / `--display` options that would tell gpg-agent where to prompt, so
pinentry has nowhere to go and fails with `Inappropriate ioctl for device`.
The isolation boundary here is the qube, not the passphrase.

## A client qube

```nix
{
  qubes.gpgSplitClient = {
    enable = true;
    vaultName = "pgp-nube";
  };
}
```

`aliasGpg` (on by default) aliases `gpg` to `qubes-gpg-client-wrapper`, but
that is a shell alias and only affects interactive shells. Tools need telling
separately -- for git:

```
[gpg]
    program = qubes-gpg-client-wrapper
```

## dom0 policy -- required, and not automated

`qixos-rebuild` only writes `admin.*` policy, at install time. Application
policy is yours to add, by hand, in dom0. Without it every request is denied.

Create `/etc/qubes/policy.d/30-split-gpg.policy` in dom0:

```
qubes.Gpg           *   dev-nube   pgp-nube   allow
qubes.GpgImportKey  *   dev-nube   pgp-nube   ask default_target=pgp-nube
```

The columns are `service argument source target action`. Files are read in
lexical order and the first match wins, so any number below `90-default.policy`
works.

Name each client qube explicitly. It is tempting to write
`@tag:created-by-qixos-admin` in the source column, since every nube carries
that tag, but that grants *every* nube on the system use of your signing key --
including any future one you add without thinking about GPG. The whole point of
split GPG is that the client list is short and deliberate.

`qubes.GpgImportKey` is `ask` rather than `allow` above because importing a
public key means running the backend's GPG parser over bytes the client chose.
That is the one routine path by which a compromised client reaches attacker-
controlled data into the vault.

## What this does and does not protect

It stops a client qube from *exfiltrating* the key. A compromised client can
still ask the backend to sign or decrypt anything, for as long as consent
lasts, and split GPG cannot show you what is about to be signed -- you approve
a request from a qube, not a document.

Consent is remembered per client qube for `QUBES_GPG_AUTOACCEPT` seconds,
upstream default 300. See the `autoAccept` option: there is no setting that
means "approve exactly one request".

For stronger separation, keep the master key in a separate offline vault and
put only subkeys in the backend, so a compromise of the backend costs you
revocable subkeys rather than the identity.
