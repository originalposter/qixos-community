#!/usr/bin/env python3
"""A switch killed by the OOM killer is reported as an OOM, not as a generic failure.

The difference matters to whoever reads the failure: one of them names the fix, which is
to give the template more RAM, and the other says only that nixos-rebuild exited
non-zero.

Unfinished, and returns early saying so. Nothing here provokes the kill it is about:
core.nix gives every nube swap on /dev/xvdc1, so a template starved of memory thrashes
instead of being killed. At memory=600 with ballooning off, a switch ran for over ten
minutes and was still going. What is missing is a way to get nixos-rebuild's nix build
actually SIGKILLed. The assertions below are written and their decision table checked
against captured output, so finishing this means providing that and deleting the early
return.

Red until the error codes are fixed. Two things are wrong today, and either one alone is
enough to lose the distinction:

  - qixos.Switch decides it was an OOM by checking whether nixos-rebuild's own return
    code is -SIGKILL. The OOM killer normally takes the nix build underneath it instead,
    so nixos-rebuild exits 1 and the check falls through to NixosRebuildError.
  - the code rides on an exit status, which is 8 bits, so 1006 arrives as 238 and
    ping_template's comparison against OomKillerError.ERROR_CODE can never match. This
    test asserts the full code rather than encoding that truncation, so it stays red
    until the codes survive the trip intact.

Passing takes both: the code, which a caller can act on, and a message naming the
out-of-memory kill, which a person can. Either alone is a half-reported failure. A bare
number says nothing about RAM, and a message with no code leaves nothing to match on.

Note that today's OOM branch in ping_template raises before the line that logs the code,
so reporting both is a change to the fix as well as to what is asserted here.

Between them the failures below say which defect is still present, so a red run points
at the next thing to change rather than only saying no.

usage: oomed_switch_reports_oom.py <flake-ref> <template>
"""
import re
import subprocess
import sys

# From qixos core's qrexec protocol. A change there has to be matched here, which is the
# price of asserting on a specific code rather than on the words around it.
OOM_ERROR_CODE = 17
NIXOS_REBUILD_ERROR_CODE = 15

# The reported switch failure, whose only structured part is the code. Read out of the
# output because the exit status is the sole other channel and it says nothing about
# which of the switch's failures happened.
REPORTED_CODE = re.compile(r"qixos\.Switch call for \[[^\]]+\] failed with:? (\d+)")

OOM_MESSAGE = re.compile(r"out-of-memory killer", re.IGNORECASE)

# The code on its own, wherever the report chooses to put it. Bounded, so a run of
# digits inside a store path cannot stand in for it.
OOM_CODE = re.compile(rf"\b{OOM_ERROR_CODE}\b")


def main(argv):
    if len(argv) != 3:
        print(f"usage: {argv[0]} <flake-ref> <template>", file=sys.stderr)
        return 2

    flake, template = argv[1], argv[2]

    result = subprocess.run(
        ["qixos-rebuild", "--flake", flake, "apply"], capture_output=True, text=True
    )
    output = result.stdout + result.stderr

    if result.returncode == 0:
        print(
            f"apply succeeded, so nothing was killed and this proves nothing. "
            f"{template} was given enough memory to evaluate its configuration.",
            file=sys.stderr,
        )
        return 1

    has_message = OOM_MESSAGE.search(output) is not None
    has_code = OOM_CODE.search(output) is not None

    if has_message and has_code:
        print(
            f"the switch on {template} reported {OOM_ERROR_CODE} and named the "
            f"out-of-memory kill"
        )
        return 0

    if has_code:
        print(
            f"the switch on {template} reported {OOM_ERROR_CODE} without saying it "
            f"was an out-of-memory kill, so the number is all anyone gets.",
            file=sys.stderr,
        )
        return 1

    if has_message:
        print(
            f"the switch on {template} named an out-of-memory kill without "
            f"reporting {OOM_ERROR_CODE}, so nothing carries it onward.",
            file=sys.stderr,
        )
        return 1

    # Neither half. Name the other failure if the output named one.
    reported = REPORTED_CODE.search(output)
    if reported is None:
        print("apply failed without reporting a switch error code:", file=sys.stderr)
        print(output.strip(), file=sys.stderr)
        return 1

    code = reported.group(1)
    if code == str(NIXOS_REBUILD_ERROR_CODE):
        print(
            f"the switch on {template} was killed but exited {code}, a generic "
            f"nixos-rebuild failure, so the kill was never detected.",
            file=sys.stderr,
        )
    else:
        print(
            f"the switch on {template} exited {code}, which is neither the "
            f"out-of-memory code {OOM_ERROR_CODE} nor a nixos-rebuild failure.",
            file=sys.stderr,
        )
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
