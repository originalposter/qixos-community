#!/usr/bin/env python3
"""A push from another qube lands in the config vault and survives a reboot.

An AppVM's root is thrown away at shutdown, so a repo anywhere but under /home is
served until the first restart and then gone. That is this test's property, and the
reboot is the only thing that can show it.

The push goes over the suite's own ssh into the nube rather than over
qixos.WriteConfigVault, which is what a real pusher uses: reaching the service would
need a dom0 line for this admin, and what the service does with a push is covered by
config-vault-accepts-a-push-through-the-service in the nube itself. What needs two
qubes here is the arriving, not the transport.

usage: config_vault_push_survives_reboot.py <vault>
"""
import os
import subprocess
import sys
import tempfile
import uuid

import harness

# Relative to the vault user's home, which is where an ssh push lands.
PUSH_PATH = "config-vault/qixos-community"
# What a reboot can take away is the repo, so the repo is what this reads. Serving it is
# a per-request upload-pack with no state of its own, and the in-nube tests cover that.
GITDIR = f"{PUSH_PATH}/.git"

# Any name will do: nothing in the vault treats one branch differently.
REF = "refs/heads/pushed-by-the-suite"


def ref_in_vault(vm):
    result = harness.ssh(vm, f"git --git-dir={GITDIR} rev-parse --verify -q {REF}")
    if result.returncode != 0:
        return "no such ref"
    return result.stdout.strip()


def push_new_commit(vm):
    """Push a commit no earlier run can have made. Its sha, or None."""
    with tempfile.TemporaryDirectory() as d:
        def git(*args, **kwargs):
            return subprocess.run(["git", "-C", d, *args], capture_output=True, text=True, **kwargs)

        git("init", "-q")
        git("-c", "user.name=qixos-test", "-c", "user.email=test@qixos.invalid",
            "commit", "-q", "--allow-empty", "-m", f"config-vault test {uuid.uuid4()}")
        sha = git("rev-parse", "HEAD").stdout.strip()

        # Forced, since the commit has no history in common with whatever is there.
        env = {**os.environ, "GIT_SSH_COMMAND": " ".join(["ssh", *harness.SSH_OPTS])}
        push = git("push", "-q", "--force", f"{vm}.qube:{PUSH_PATH}", f"HEAD:{REF}", env=env)
        if push.returncode != 0:
            print(f"push to {vm} over ssh failed: {push.stderr.strip()}", file=sys.stderr)
            return None
        return sha


def main(argv):
    if len(argv) != 2:
        print(f"usage: {argv[0]} <vault>", file=sys.stderr)
        return 2
    vm = argv[1]

    if not harness.boot(vm):
        return 1

    # ssh answers on the template's closure, before the vault's own switch has run the
    # unit that creates the repo. Run alone against a fresh vault, the push would beat it.
    if not harness.wait_for(vm, f"test -d {PUSH_PATH}", "the vault's repo to exist"):
        return 1

    sha = push_new_commit(vm)
    if sha is None:
        return 1

    for when in ("after the push", "after a reboot"):
        if when == "after a reboot" and not harness.boot(vm):
            return 1
        # The switch's deadline, because /home is mounted by the boot this waits on.
        present = f'test "$(git --git-dir={GITDIR} rev-parse --verify -q {REF})" = {sha}'
        if not harness.wait_for(vm, present, f"{REF} at {sha}"):
            print(f"{vm} has {ref_in_vault(vm)} for {REF} {when}, expected {sha}", file=sys.stderr)
            return 1

    print(f"{vm} kept the pushed commit, before and after a reboot")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
