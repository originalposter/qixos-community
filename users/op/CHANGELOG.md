# Changelog

## Unreleased

### A config vault serving git repos to other nubes
`blueprints.config-vault` serves the repos under `~/config-vault` over the
`qixos.ReadConfigVault` qrexec service, which takes the repository as its service
argument. It creates none, so make them yourself:

    git init ~/config-vault/qixos-community        # a worktree to edit in
    git init --bare ~/config-vault/other.git       # or bare, if nobody edits here

A repo with a worktree can be edited in place with no git knowledge at all:
`refs/qixos/live` carries whatever is on disk, snapshotted when a template fetches, so a
nube can build an edit nobody committed. Commit instead and the branch is a normal
auditable history. Both refs exist; the nube's `remoteFlake.url` picks.

`basic-template` routes `git+ssh://<qube>.qube/<repo>` through the service, so a
`remoteFlake` can be
`git+ssh://config-vault-nube.qube/qixos-community?ref=refs/qixos/live&dir=...`. No key
and no secret: for a `.qube` host git's ssh command runs qrexec instead of ssh.

Pushes come over the `qixos.WriteConfigVault` service, which also takes the repository
as its argument. There is no sshd on the vault and no key: the calling qube is the
principal and the dom0 line is the whole of the authority, so what a pusher may do is
readable in the policy file. Write `ask` instead of `allow` for a prompt on every push.
A push to a branch the vault has checked out lands only when the vault's worktree is
clean, and says which files are in the way when it is not.

The dom0 policy, with the repository as the argument so a reader is granted the repos it
needs rather than the vault entire:

    qixos.ReadConfigVault  +qixos-community @tag:created-by-qixos-admin config-vault-nube allow
    qixos.WriteConfigVault +qixos-community review-nube                 config-vault-nube ask

`*` in place of `+qixos-community` covers every repository in the vault.

### Language servers and LLM agents are separate from the dev-nube blueprint
Import `blueprints.dev-lsp` and `blueprints.llm-tools` beside it; the agents' nube is now
`nubes/appvms/dev-llm-nube`. Adds Haskell, OCaml, Idris, Lean and Zig, and the agents
herdr, paseo, pi, opencode and oh-my-pi. A template building a dev nube with both needs
`volumes.root` above the 30 GiB default.

## v0.2.0

### A test suite for QixOS itself
Built a test suite that can be found in `users/op/tests/`.
The test suite is supposed to run inside of a separate `qixos-admin-test` VM which
creates its own test realm. It supports various types of tests such as ones that need
admin APIs for creating, deleting or changing VMs as well as tests that run inside of
a nube.

Supports an API for modules to define their own tests that easily and automatically get
run by the test suite.


### split-gpg backend module
A module that serves a GPG private key to other nubes over qrexec, so a key can live in one
nube and be used from the rest without leaving it.


### Password manager nube
`qix-pw` is a qix specific password manager. It works by using `pass`, `rofi` and `qrexec`
to let users choose a password and send it to the desired nube and have it enter the clipboard.


### split-ssh nube
Add the split ssh module which allows nube A to temporarily use ssh keys stored in nube B


### Templates reach github and gitlab over update proxy
The `basic-template` blueprint configures templates to reach github and gitlab ssh endpoints through
the qubes update proxy.


### Remove home-manager as a first class citizen in nube configuration format
Home-manager used to be a top level attribute in the nube configuration format for each nube.
We de-privilege home-manager and point users to the nixos home-manager module instead.


### The repository moved to GitHub
References to codeberg.org now name github.com. The Codeberg repo is deprecated.
