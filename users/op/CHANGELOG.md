# Changelog

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
