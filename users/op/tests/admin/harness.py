"""Shared machinery for the admin half of the suite.

The transport into a nube, the power controls around it, and the reads more than one
admin test needs. A module rather than helpers in `run` so that an admin test stays
runnable by hand while debugging.

Nothing here asserts. A helper returns what it found, or None if it could not look.
"""
import subprocess
import sys
import time

# Long enough for a cold nube to boot and bring up sshd.
SSH_DEADLINE = 180

# Long enough for a nube to stop on its own before we call it stuck.
SHUTDOWN_DEADLINE = 120

# No host key pinning, and nothing written to the user's known_hosts. A test nube has no
# stable identity to pin: it is destroyed and recreated under the same name each run, and
# it regenerates its host keys on every boot besides, which the runner triggers itself by
# rebooting the nube before testing it. Recording a key here could only produce false
# alarms. What the connection is trusted on instead is the transport: qrexec, to a qube
# this runner just created, admitted by dom0 policy, with no network path to interpose on.
#
# The per-boot rotation is a defect rather than a fact of life, since /etc/ssh sits on the
# root volume an AppVM discards. README.md already lists a test for it under Persistence.
SSH_OPTS = [
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=5",
    "-o", "UserKnownHostsFile=/dev/null",
    "-o", "StrictHostKeyChecking=no",
    # Otherwise every connection announces that it "permanently added" a host key, into
    # the middle of the report, having stored it in /dev/null.
    "-o", "LogLevel=ERROR",
]


def ssh(vm, *command):
    """Run a command in a nube over the qrexec ssh tunnel.

    ssh joins its arguments and hands them to the remote login shell, so a single
    multi-line string argument works as a shell script.
    """
    return subprocess.run(
        ["ssh", *SSH_OPTS, f"{vm}.qube", *command],
        capture_output=True, text=True,
    )


def wait_for_ssh(vm):
    """Block until the nube answers, or give up.

    The transport and nothing else. Whether a nube is ready for its own tests depends
    on what those tests need, so each test waits for its own preconditions.
    """
    deadline = time.monotonic() + SSH_DEADLINE
    last = ""

    while time.monotonic() < deadline:
        result = ssh(vm, "true")
        if result.returncode == 0:
            return True
        last = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else ""
        time.sleep(2)

    # With ssh's reason, not without it. A booting nube, a qube that never started, a
    # policy denial and a rejected host key all take this path, and they are not
    # distinguishable from the outside by anything except what ssh said.
    print(f"{vm} did not answer ssh within {SSH_DEADLINE}s", file=sys.stderr)
    if last:
        print(f"  last error: {last}", file=sys.stderr)
    return False


def is_running(vm):
    """Whether the qube is up. qvm-check exits 0 while it is running."""
    return subprocess.run(
        ["qvm-check", "--running", vm], capture_output=True, text=True
    ).returncode == 0


def shut_down(vm):
    """Stop a nube and wait for it to actually be down.

    Polled rather than `qvm-shutdown --wait`, which needs the admin API's event stream.
    dom0 refuses `admin.Events` to this admin qube by design, since that stream is
    dom0-targeted and cannot be scoped to a management tag, so `--wait` floods the log
    with denials and succeeds only when its fallback happens to win the race.
    """
    stop = subprocess.run(["qvm-shutdown", vm], capture_output=True, text=True)
    if stop.returncode != 0:
        print(f"could not shut down {vm}: {stop.stderr.strip()}", file=sys.stderr)
        return False

    deadline = time.monotonic() + SHUTDOWN_DEADLINE

    while time.monotonic() < deadline:
        if not is_running(vm):
            return True
        time.sleep(2)

    print(f"{vm} was still running {SHUTDOWN_DEADLINE}s after shutdown", file=sys.stderr)
    return False


def start(vm):
    """Start a nube. Already running counts as success, since qvm-start fails on one."""
    if is_running(vm):
        return True

    result = subprocess.run(["qvm-start", vm], capture_output=True, text=True)
    if result.returncode != 0:
        print(f"could not start {vm}: {result.stderr.strip()}", file=sys.stderr)
        return False
    return True


def boot(vm):
    """Boot a nube from scratch and wait for it to answer ssh.

    Stopped first even if already running. An AppVM takes its config and its root
    volume at boot, so one that was up before the switch has neither.
    """
    return shut_down(vm) and start(vm) and wait_for_ssh(vm)


# Host key reads, shared because three tests need the same answers.

# Type and blob only. The trailing comment field carries a hostname, and including it
# would let a cosmetic change look like a rotation.
_PUBLIC_HOST_KEYS = r"""
found=0
for f in /etc/ssh/ssh_host_*_key.pub; do
  [ -e "$f" ] || continue
  found=1
  awk '{print $1, $2}' "$f"
done
[ "$found" = 1 ]
"""

# sudo because the private halves are root-only. qixos core puts the primary account
# in wheel with passwordless sudo (core.nix).
_PRIVATE_HOST_KEY_HASHES = r"""
found=0
for f in /etc/ssh/ssh_host_*_key; do
  [ -e "$f" ] || continue
  found=1
  sudo sha256sum "$f"
done
[ "$found" = 1 ]
"""

_ETC_SSH_HASHES = "sudo find /etc/ssh -type f -exec sha256sum {} +"

# Narrowed by name and then hashed, since hashing the whole store would be far too
# slow. nixpkgs ships dummy keys under these names, so the caller matches on content.
_STORE_HOST_KEYS = "find /nix/store -name 'ssh_host_*_key' -type f -exec sha256sum {} +"


def public_host_keys(vm):
    """The nube's public host keys as a set of "<type> <blob>" strings.

    None if there are none, since an empty set compares equal to another empty set and
    would pass a comparison meant to involve two real identities.
    """
    result = ssh(vm, _PUBLIC_HOST_KEYS)
    if result.returncode != 0:
        print(f"could not read host keys on {vm}: {result.stderr.strip()}", file=sys.stderr)
        return None

    keys = {line.strip() for line in result.stdout.splitlines() if line.strip()}
    return keys or None


def private_host_key_hashes(vm):
    """sha256 of each private host key, as {hash: path}.

    Hashed on the nube, so no private material crosses the tunnel.
    """
    result = ssh(vm, _PRIVATE_HOST_KEY_HASHES)
    if result.returncode != 0:
        print(f"could not hash host keys on {vm}: {result.stderr.strip()}", file=sys.stderr)
        return None

    hashes = {}
    for line in result.stdout.splitlines():
        parts = line.split(maxsplit=1)
        if len(parts) == 2:
            hashes[parts[0]] = parts[1].strip()
    return hashes or None


def etc_ssh_hashes(vm):
    """sha256 of every file in /etc/ssh, as {hash: path}.

    Wider than the private key paths, to catch a key copied in under another name.
    """
    result = ssh(vm, _ETC_SSH_HASHES)
    if result.returncode != 0:
        print(f"could not hash /etc/ssh on {vm}: {result.stderr.strip()}", file=sys.stderr)
        return None

    hashes = {}
    for line in result.stdout.splitlines():
        parts = line.split(maxsplit=1)
        if len(parts) == 2:
            hashes[parts[0]] = parts[1].strip()
    return hashes


def store_host_key_hashes(vm):
    """sha256 of every file under /nix/store named like a private host key, as {hash: path}.

    Empty is the expected answer, so {} means nothing matched and None means the search
    itself failed.
    """
    result = ssh(vm, _STORE_HOST_KEYS)
    if result.returncode != 0:
        print(f"could not search the store on {vm}: {result.stderr.strip()}", file=sys.stderr)
        return None

    hashes = {}
    for line in result.stdout.splitlines():
        parts = line.split(maxsplit=1)
        if len(parts) == 2:
            hashes[parts[0]] = parts[1].strip()
    return hashes
