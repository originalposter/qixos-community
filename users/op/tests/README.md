# qixos test suite

Tests that need real qubes. qixos core keeps what runs without them: pytest over the pure
parts of `qixos-rebuild`, and nix-level tests of `mkNubeCluster` against synthetic input.

## Architecture

### Concepts

**Test** - a program that exits zero or non-zero. Nothing else is asked of it.

**Admin test** - runs on the test admin. Reads qubes-level state through the admin API and
reaches into nubes over ssh when it has to. Owns anything spanning two nubes, and anything
asserting on what survives a reboot, since a test inside a nube cannot outlive its own
context.

**In-nube test** - runs inside the nube that declares it. A module assigns to
`qixosTests.tests` in a file it imports alongside itself, which puts the test on `$PATH`
behind `run-tests`. Tests then sit next to the logic they cover and read that module's
options instead of duplicating its defaults. Any nube importing the module gets them by
setting `qixosTests.enable`.

**Scenario** - a fleet state and the tests that read it. Its `setup` is the outer config to
apply before they run, or `None` when its tests apply for themselves.

**Runner** - `run`, the only orchestrator. Walks the scenarios in order, applies each one's
setup, runs its tests, prints one report and exits non-zero if anything failed.

### How they fit together

Admin and in-nube tests are siblings gathered by one program, not nested frameworks. For
each scenario the runner halts every suite qube, applies the setup if there is one, halts
them again so the template commits the root volume its AppVMs snapshot, then runs the
tests and prints `PASS`/`FAIL <scenario>/<test>` for each.

An in-nube test is reached over `qubes.Ssh`, so there is no report service to write and
the script a human runs by hand while debugging is the one the runner invokes. The runner
boots the nube, asks `run-tests --list`, runs `run-tests`, and reconciles what came back
against what was declared. Anything declared but not reported is a failure, which is what
stops a nube that died partway through looking green.

Four invariants hold this together:

- **Applying a scenario evicts the previous one's AppVMs.** That is what keeps scenarios
  from depending on each other. Qubes without `deleteOnRemoval` survive it, templates
  included, so a cluster template is cloned and built once rather than once per scenario.
  It is also the one channel by which scenarios contaminate each other: a test that writes
  to a template writes to shared state.
- **Every scenario runs, including after a failure.** Stopping early would strand later
  ones behind tests that are red on purpose until the bug they describe is fixed.
- **A nube is rebooted before its tests run.** An AppVM takes its config and its root
  volume at boot, so one that was already up when the template switched carries neither.
- **The runner waits only for ssh.** What else a nube needs depends on its tests, so each
  waits for its own preconditions. A nube answers ssh well before it has an X server.

Where a new test goes depends on whether apply is part of what it tests. If it is, the test
owns the apply and gets a scenario of its own with no setup, because running apply
invalidates the fleet every other test in that scenario is reading. If it is not, it joins
a scenario with a setup and must not run `qixos-rebuild` itself.

### Isolation

A separate management qube, `qixos-admin-test`, with its own management tag that dom0
applies and nothing can forge. Every policy line is scoped to that tag, so a test run
cannot reach a production nube. It clones its own base template, so it shares no root
volume with the production admin. Every qube the suite creates is named `test-*`, and
teardown goes by that prefix rather than by the management tag, which is also on the admin,
its base template and any deliberately kept cluster template.

### Where things live

| path | what |
| --- | --- |
| `run` | the orchestrator. `SCENARIOS` is the wiring |
| `to-test-admin` | ships this tree to `qixos-admin-test` and drives it |
| `admin/` | admin tests, one file each, runnable by hand |
| `admin/harness.py` | ssh transport, power controls, and the reads several tests share |
| `runner.nix` | the in-nube half: turns `qixosTests.tests` into `run-tests` |
| `nubes/<name>/` | inner configs the scenarios build |
| `outer-configs/<name>/` | fleet definitions a scenario's `setup` applies |

`runner.nix` sits inside op's flake because a module cannot import across a flake boundary,
so a harness anywhere else could not be pulled in by the module whose tests it carries.

## Setup: dom0 policy the tester must add

Two lines no config in this repo can install for you, because dom0 policy is dom0's. Put
them in `/etc/qubes/policy.d/56-qixos-test-ssh.policy`, after the `55-` file `install.sh`
writes:

```
qubes.Ssh * qixos-dev-nube    qixos-admin-test                     allow
qubes.Ssh * qixos-admin-test  @tag:created-by-qixos-admin-test     allow
```

The first points *into* the test admin from an ordinary development nube, so driving the
suite does not require sitting in dom0 or at the console. It is a real grant: a shell in
`qixos-admin-test` is effectively root there, and that qube can create and destroy any qube
under its tag. Delete the file to revoke. The second is the runner reaching test nubes,
scoped to the management tag so a scenario can create a nube and reach it without a policy
edit.

## Using it

From a dev nube. No commit is involved; the working tree goes over as it stands.

```
./to-test-admin push     ship the tree and stop there
./to-test-admin test     ship and run the whole suite
./to-test-admin demo     ship and apply the split password demo
```

On the admin:

```
./run                      every scenario
./run <scenario>           one scenario. Nothing after it applies, so its nubes stay up
./run <scenario> <test>    one test, with its scenario's setup still applied first
./run --help               list scenarios and their tests
```

Straight from a nube, with no apply at all, which is the fastest loop while debugging:

```
ssh <nube>.qube run-tests           every test the nube declares
ssh <nube>.qube run-tests --list    names only
ssh <nube>.qube run-tests <name>    one
```

## Adding a test

### Which kind

In-nube unless it cannot be. Those are cheaper to run, live next to the code they cover,
and can read their module's options instead of duplicating its defaults.

It has to be an admin test if it spans two nubes, if it has to survive the destruction of
its own context by a reboot, a shutdown or the switch, or if it acts with privilege the
nube lacks, such as power control or the admin API.

Then, separately: is `qixos-rebuild apply` part of what you are testing? If it is, the test
owns the apply and needs a scenario of its own with `setup=None`, because running apply
invalidates the fleet every other test in a scenario is reading. If it is not, it joins a
scenario that has a setup and must not call `qixos-rebuild` itself.

### An admin test

1. An executable under `admin/`, named for the property it asserts, in snake_case:
   `appvm_host_keys_are_not_the_templates.py`, not `test_*.py`. `run` executes the file
   directly, so it needs its `#!/usr/bin/env python3` and its exec bit.
2. Take the qubes it reads as arguments rather than hardcoding them, so it stays runnable
   by hand while debugging. Exit 0 for pass, 1 for fail, 2 for a usage error.
3. `import harness` for the transport and the power controls: `harness.boot(vm)` for a
   nube that must be freshly booted, `harness.ssh(vm, script)` to run something in it,
   `harness.shut_down` and `harness.start` when you need the halves separately.
4. Reads that a second test needs go in `harness.py`. Nothing there asserts: a helper
   returns what it found, or `None` if it could not look, and the test decides what that
   means.
5. Wire it into a scenario in `SCENARIOS`, in `run`:

   ```python
   ("ssh-keys-persist", lambda: admin_test(
       "./users/op/tests/admin/ssh_host_keys_survive_reboot.py",
       "test-smoke-ssh-a",
   )),
   ```

   The label is kebab-case and is what the report prints. Paths are relative to the repo
   root, which `run` chdirs to whatever the caller's cwd.

### An in-nube test

1. A module declares its own tests, in `<module>-tests.nix` beside `<module>.nix`.
   `<module>.nix` imports it, along with `../../tests/runner.nix`:

   ```nix
   imports = [
     ../../tests/runner.nix
     ./receiver-tests.nix
   ];
   ```

2. Assign to `qixosTests.tests`. The attribute name must match a program at `bin/<name>`
   in its package, so one name identifies the test in the config, on disk, and in the
   report. The `mkTest` helper in the existing test files is the shape:

   ```nix
   qixosTests.tests = {
     password-paste-service-registered =
       mkTest "password-paste-service-registered" ''
         service=$(qixos-find-qrexec-service ${cfg.serviceName})
       '';
   };
   ```

3. Gate the whole block on the module's own enable option, so a nube that imports the
   module and leaves it off does not advertise tests that could not pass.
4. Name it kebab-case, prefixed by its family: `password-paste-*`, `password-menu-*`.
5. The nube needs `qixosTests.enable = true` to get `run-tests` on `$PATH`.
6. A test belonging to no module goes in the nube's config directly.
7. Nothing to add to `run` if a scenario already names that nube. Its `nube_tests` call
   picks up anything newly declared, and the declared-versus-reported reconciliation means
   a test that fails to run is reported rather than skipped.

### A new scenario

Prefer joining `smoke`. A new scenario costs another template clone and a full build.

1. An outer config at `outer-configs/<name>/flake.nix`, with every qube named
   `test-<name>-*` so teardown finds them by prefix.
2. Inner configs at `nubes/<name>/`, or point `localFlake` at an existing one.
3. A `Scenario` in `SCENARIOS`, with `setup` pointing at the outer config's flake output,
   or `setup=None` if its tests apply for themselves.

### Before you trust it

Watch it fail. `./run <scenario> <test>` reruns one test with its setup applied, and
`ssh <nube>.qube run-tests <name>` reruns one in-nube test with no apply at all. Then add
its line to the list below.

## Tests

### smoke

Fleet: `outer-configs/smoke`, one template and four AppVMs, inner configs in `nubes/smoke`.

**ssh host key identity** (admin). One property, three assertions: an AppVM should have an
ssh identity of its own that it keeps. Regression tests for QIX-004 in qixos'
`docs/KNOWN_VULNERABILITIES.md`.

- `ssh-keys-not-the-templates` - an AppVM neither presents nor holds its template's host keys
- `ssh-keys-persist` - an AppVM keeps its host keys across a reboot. Masked by the above, since a key baked into the template survives a reboot too, so it runs after it
- `ssh-keys-distinct-per-nube` - two AppVMs of one cluster share no host key

**split password entry, receiver** (in-nube, `test-smoke-password`). The receiver owns the
clipboard, serves the username, and swaps in the password once the username has been
pasted. What makes it hard is that one Ctrl-V is not one selection request, and that a
client keeps what it was given until the selection changes hands.

- `password-paste-service-registered` - the qrexec service is registered
- `password-paste-hands-over-username-then-password` - the username is served first, the password after it has been pasted
- `password-paste-negotiation-then-fetch-is-one-paste` - asking which targets are on offer and then fetching is one paste, not two
- `password-paste-serves-one-burst-once` - two requests carrying one keystroke's timestamp are one paste
- `password-paste-groups-unstamped-requests-by-time` - requests stamped `CurrentTime` say nothing about their keystroke, so they group by the settle window
- `password-paste-late-requests-still-get-the-username` - a request stamped inside the username's ownership is answered with it however late it arrives
- `password-paste-takes-the-selection-again-for-the-password` - the handover retakes the selection, the only thing that tells a client its copy is stale
- `password-paste-no-username-means-no-handover` - a single-line payload is served as the password throughout, owner staying put
- `password-paste-clears-when-nobody-pastes` - nothing pasted at all clears the password rather than leaving it

**split password entry, menu** (in-nube, same nube). rofi, pass, `qrexec-client-vm` and
`qubesdb-read` are stood in for, and the stand-in records how it was called.

- `password-menu-sends-the-username-then-the-password` - username, newline, password, nothing after it, compared byte for byte
- `password-menu-names-this-qube-to-dom0` - the call names this qube, which is what lets dom0 redirect it and what makes a policy that stopped redirecting fail closed
- `password-menu-without-the-flag-sends-only-the-password` - one line, the shape that tells the receiver to skip the handover
- `password-menu-username-is-what-follows-the-last-separator` - so a service name may contain one, and the entry is still looked up whole
- `password-menu-refuses-an-entry-without-a-username` - a hard error, decrypting nothing and sending nothing, rather than a quiet fall back to password-only

### memory

Its own scenario because it applies, and because it removes the nube it asserted on.

- `memory-matches-expected` - a nube's memory is what the outer config asked for

### oom

Its own scenario because its apply is the thing under test, meant to be killed part way.

- `oom-switch-reports-oom` - an OOM-killed switch is reported as an OOM, not a generic nixos-rebuild failure. Unfinished: nothing provokes the kill yet, so it returns early saying so

### Written, not wired

- `admin/apply_is_idempotent.py` - applying an already converged config leaves nothing pending. In no scenario yet

## Tests to write

**The switch.** A user unit in the AppVM config but not the template's gets started, asserted
absent before and present after. The GUI daemon is not restarted across the switch. The
switch job is not killed by its own activation script. The switch ran to completion. The
AppVM's toplevel is present in the template's store. Two AppVMs of one cluster differ while
sharing a store. A second boot converges the same way as the first.

**Switch inhibitors**, three of their own, since only `boot` and `dry-activate` skip the
pre-switch check and the AppVM switch runs `switch-to-configuration test`. A template's
`system.switch.inhibitors` matches every AppVM's in its cluster, checkable at eval time. A
divergence really does fail the switch rather than passing quietly. An inhibitor meant to
force `boot` on the template path fires when it should, keyed on something identical between
a template and its AppVMs but changing between generations.

**Secrets**, read from a sibling nube, which holds the same ciphertext and should still be
unable to read anything. A secret decrypted in one nube is not readable from a sibling. The
sentinel does not appear anywhere in the shared store. A sibling cannot decrypt, having the
ciphertext but not the identity. The decryption identity resolves to `/rw`, not the root
volume. No secrets on the root volume, as a whitelist of mutable non-store files so anything
new fails rather than having to be anticipated.

**Orchestration.** Apply twice, second diff empty. Rename renames rather than recreates.
Removal honours `deleteOnRemoval`, both settings. A changed property reconciles.
`switch --only` leaves the other templates alone. Teardown removes the qubes the scenario
created, by name prefix.

**Configuration.** A nube's built config contains what it declared. Evaluating is not enough:
a config can evaluate cleanly and silently contain nothing.

**Failure.** Break a switch deliberately and assert the nube still boots.

**Sequences.** Several of the above are sequences rather than one pass: apply twice, rename
and check, reboot between two checks, break a switch and expect the failure. Those need the
runner to take a description of what to do rather than doing one hardcoded thing. Deferred
until there is a second sequence to compare against the first. The likely answer is a script
calling `qixos-rebuild` and the runner's own subcommands, generated by nix.

## Not covered

dom0's own state is not reachable from the admin, so anything only visible there stays a
manual check.

## Practices

- watch a test fail before trusting it to pass
- poll for a condition with a deadline; never sleep for a guessed duration
- prefer machine state to log text, which changes for harmless reasons
- read-only tests before mutating ones, and a mutating test says so
- anything genuinely destructive gets its own nube
- one command runs the suite
