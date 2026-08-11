# qixos test suite

Nothing here runs yet. This is the intended architecture and the tests we want.

## Where it lives

qixos core keeps only what runs without Qubes: pytest over the pure parts of
`qixos-rebuild`, and nix-level tests of `mkNubeCluster` against synthetic input.
Everything that needs real qubes lives here.

## Isolation

A separate management qube, `qixos-admin-test`, with its own management tag that dom0
applies and nothing can forge. Every policy line is scoped to that tag, so a test run
cannot reach a production nube. It clones its own base template too, so it shares no
root volume with the production admin.

## The pieces

Three things, with different owners.

**In-nube tests** are declared in a nube's own nix config. The declaration installs them
as scripts on `$PATH` and exposes one qrexec service that runs them and prints results.
That covers a config author's own tests and ours alike: ours live in a shared module that
the test nubes import.

**Admin tests** are ordinary executables in this tree. They assert on qubes-level facts
through the admin API, such as whether a qube was created, renamed or destroyed, and need
no transport, because they run where the runner runs.

**The runner** is the only orchestrator. It
1. reconciles to empty
2. applies an outer config with `qixos-rebuild`
3. starts the nubes and calls each nube's qrexec service
4. runs the admin tests
5. prints one report and exits non-zero if anything failed.

So the outer and inner tests are siblings gathered by one program, not nested frameworks.

Reconciling to empty comes first, not only last. Teardown does not run when a run
crashes, which is exactly when it matters.

## Sequences

That fixed order covers a first round of tests, but several of the ones we want are
sequences rather than one pass: apply twice and expect an empty diff, rename a qube and
check it was not recreated, reboot between two checks, break a switch and expect the
failure. Those need the runner to take a description of what to do instead of doing one
hardcoded thing, and a description carrying repetition, expected failure and ordering is
a small language whether or not we call it one.

Deferred until there is a second sequence to compare against the first, since that is
when its shape becomes visible rather than guessed. The likely answer is that the runner
accepts a script calling `qixos-rebuild` and its own subcommands, with nix generating
that script.

## Tests

A test is a script. What it cannot do is act with privilege the nube lacks, or survive
the destruction of its own context by a reboot, a shutdown or the switch. Those belong to
the runner.

Because tests may mutate, they run in a declared order with read-only ones first, and a
mutating test says so. Anything genuinely destructive gets its own nube.

A test that never ran needs to be distinguishable from one that failed, so the set of
declared tests has to be known rather than inferred from whatever reported back.

## Tests to write

### The switch

- a user unit in the AppVM config but not the template's gets started. Has to assert
  absent before and present after, or it passes when the switch does nothing
- the GUI daemon is not restarted across the switch
- the switch job is not killed by its own activation script
- the switch ran to completion
- the AppVM's toplevel is present in the template's store
- two AppVMs of one cluster differ while sharing a store
- a second boot converges the same way as the first

### Persistence

- an AppVM keeps its ssh host keys across a reboot. We want this, and `/etc/ssh`
  currently sits on the root volume, which an AppVM discards
- no secrets on the root volume: treat the set of mutable non-store files as a
  whitelist, so anything new fails the test instead of having to be anticipated

### Orchestration

- apply twice, second diff is empty
- rename renames rather than recreates
- removal honours `deleteOnRemoval`, both settings
- a changed property reconciles
- `switch --only` leaves the other templates alone
- teardown leaves no qube carrying the management tag

### Configuration

- a nube's built config contains what it declared. Evaluating is not enough; a config
  can evaluate cleanly and silently contain nothing

### Failure

- break a switch deliberately and assert the nube still boots

## Not covered

dom0's own state is not reachable from the admin, so anything only visible there stays
a manual check.

## Practices

- watch a test fail before trusting it to pass
- poll for a condition with a deadline; never sleep for a guessed duration
- prefer machine state to log text, which changes for harmless reasons
- one command runs the suite
