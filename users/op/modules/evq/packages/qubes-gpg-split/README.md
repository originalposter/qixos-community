# Split GPG for nubes

Private keys live in one network-isolated qube (the **backend**). Other qubes
(**clients**) ask it to sign and decrypt over qrexec, and never see the key.
The backend shows a consent dialog and a tray notification on every request.

This directory has three parts:

| Path | What it is |
|---|---|
| `package/` | upstream `qubes-app-linux-split-gpg`, resholved for NixOS |
| `server/` | `qubes.gpgSplitServer` -- the module for the key-holding qube |
| `client/` | `qubes.gpgSplitClient` -- the module for consuming qubes |

## The backend qube

It must have `netvm = "none"` in the outer config - that isolation is the entire point, and nothing in the module enforces it.

```nix
{
  qubes.gpgSplitServer.enable = true;
}
```

The module installs no `gpg` of its own - the qrexec services carry a pinned
one internally, so add `gnupg` to the qube's `systemPackages` if you want to
manage the keyring by hand.

Import or generate keys inside that qube with ordinary `gpg`.

### Passphrases

A passphrase on the backend key works, and is worth having. Set `pinentry` to
a graphical one:

```nix
{
  qubes.gpgSplitServer = {
    enable = true;
    pinentry = pkgs.pinentry-gnome3;
  };
}
```

That gets you a prompt in the vault on **every** operation, since
`passphraseCacheSeconds` defaults to 0. It is the guarantee `autoAccept` cannot
give: the qrexec consent dialog approves a *qube* for a window of time, this
approves each individual use of the key. Same shape as `ssh-add -c` in the
split-SSH vault.

It has to be a graphical pinentry. `pinentry-curses` fails with `Inappropriate
ioctl for device`, because nothing in the qrexec path has a controlling
terminal. That error is often read as proof that passphrases cannot work here
at all, sometimes with the supporting claim that the client strips the
`--ttyname` / `--display` options that would redirect the prompt. It does strip
them -- but those are the *client's*, and the backend's gpg was never going to
use them. It uses its own environment, and it has a display: qrexec services
running as the default user are forked from `qrexec-fork-server`, which
`qubes-gui-agent` autostarts inside the graphical session. That is the same
reason upstream's zenity consent dialog and its `notify-send` work at all.

gpg hands its own `DISPLAY` to the agent per connection, so the prompt appears
in the vault even though the agent is socket-activated by systemd and has no
display of its own. `--batch`, which `gpg-server` forces, does not suppress it
either; it governs gpg's own prompts, not the agent's pinentry.

Leaving `pinentry` unset keeps the agent unconfigured, which in practice means
a passphraseless key. That is a defensible choice -- the isolation boundary is
the qube -- but it is a choice, not a constraint.

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
separately - for git:

```
[gpg]
    program = qubes-gpg-client-wrapper
```

## dom0 policy - required, and not automated

`qixos-rebuild` only writes `admin.*` policy, at install time. Application
policy is yours to add, by hand, in dom0. Without it every request is denied.

Create `/etc/qubes/policy.d/30-split-gpg.policy` in dom0:

```
qubes.Gpg           *   dev-nube   pgp-nube   ask default_target=pgp-nube
qubes.Gpg           *   @anyvm     @anyvm     deny

qubes.GpgImportKey  *   dev-nube   pgp-nube   ask default_target=pgp-nube
qubes.GpgImportKey  *   @anyvm     @anyvm     deny
```

The columns are `service argument source target action`. Files are read in
lexical order and the first match wins, so any number below `90-default.policy`
works.

Four things about that, each of which is easy to get wrong in the permissive
direction:

**`ask`, not `allow`.** Upstream ships `$anyvm $anyvm ask` for both services;
`allow` is *more* permissive than the default you are overriding. `allow` means
no dom0 prompt at all, so with a passphraseless key and the 300-second
`autoAccept` window, a single approval buys a compromised client five minutes
of unattended signing with no trusted UI anywhere in the loop. The dom0 prompt
is the only one drawn outside the qubes involved. `allow` is defensible once
the vault prompts per operation (`pinentry` set, cache 0) and you have decided
the vault's own dialog is enough -- but decide it, do not inherit it.

**Terminate each block with `deny`.** Without it you are relying on the
implicit default at the bottom of the stack, which means a later-read file
appearing to be the thing that permits GPG. Denying explicitly puts the whole
decision for a service in one file.

**Name each client qube.** It is tempting to write
`@tag:created-by-qixos-admin` in the source column, since every nube carries
that tag, but that grants *every* nube on the system use of your signing key --
including any future one you add without thinking about GPG. The whole point of
split GPG is that the client list is short and deliberate.

**Pin the target.** Naming `pgp-nube` in the target column rather than `@anyvm`
keeps the `ask` dialog from offering the client's choice of destination.
`default_target=` only preselects; the target column is what constrains.

`qubes.GpgImportKey` deserves its `ask` on its own merits: importing a public
key means running the backend's GPG parser over bytes the client chose. That is
the one routine path by which a compromised client reaches attacker-controlled
data into the vault.

## What this does and does not protect

It stops a client qube from *exfiltrating* the key. A compromised client can
still ask the backend to sign or decrypt anything, for as long as consent
lasts, and split GPG cannot show you what is about to be signed -- you approve
a request from a qube, not a document.

Consent is remembered per client qube for `QUBES_GPG_AUTOACCEPT` seconds,
upstream default 300. See the `autoAccept` option: no value of it means
"approve exactly one request". A passphrase with `passphraseCacheSeconds = 0`
does give you that, one layer down -- gpg-agent prompts per operation
regardless of what the qrexec dialog has already waved through.

For stronger separation, keep the master key in a separate offline vault and
put only subkeys in the backend, so a compromise of the backend costs you
revocable subkeys rather than the identity.
