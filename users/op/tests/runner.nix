# The in-nube half of the suite: turns the tests a nube declares in its own config
# into one `run-tests` command on PATH.
#
# `run-tests --list` prints the declared names without running anything, which is what
# lets the runner tell a test that failed from one that never ran. That only works if
# the list and the run come from the same place, so both are generated from
# `qixosTests.tests` rather than written down twice.
{ pkgs, lib, config, ... }:
let
  cfg = config.qixosTests;

  # `name:path` pairs. Attribute order is alphabetical, which is arbitrary but at
  # least stable across runs. Declared ordering is not expressible yet and starts to
  # matter as soon as one test mutates state another reads.
  entries = lib.mapAttrsToList (name: pkg: ''  "${name}:${pkg}/bin/${name}"'') cfg.tests;

  runTests = pkgs.writeShellApplication {
    name = "run-tests";
    runtimeInputs = [ pkgs.gnused ];
    text = ''
      tests=(
${lib.concatStringsSep "\n" entries}
      )

      list_names() {
        local t
        for t in "''${tests[@]}"; do
          echo "''${t%%:*}"
        done
      }

      # A test's own output is captured and indented rather than let through, so a
      # test that prints the word FAIL cannot be mistaken for a verdict line.
      run_one() {
        local name=$1 bin=$2 out status=0
        out=$("$bin" 2>&1) || status=$?

        if [ "$status" -eq 0 ]; then
          echo "PASS $name"
        else
          echo "FAIL $name"
        fi

        [ -z "$out" ] || printf '%s\n' "$out" | sed 's/^/    /'
        return "$status"
      }

      case "''${1:-}" in
        --list)
          list_names
          exit 0
          ;;
        -h|--help)
          echo "usage: run-tests [--list | <name>]"
          exit 0
          ;;
      esac

      rc=0

      # A name runs just that test, no argument runs all of them. `found` keeps a name
      # that does not exist (exit 2) distinct from a test that ran and failed (exit 1).
      if [ "$#" -gt 0 ]; then
        found=0
        for t in "''${tests[@]}"; do
          [ "''${t%%:*}" = "$1" ] || continue
          found=1
          run_one "''${t%%:*}" "''${t#*:}" || rc=1
        done

        if [ "$found" -eq 0 ]; then
          echo "no such test: $1" >&2
          exit 2
        fi
      else
        for t in "''${tests[@]}"; do
          run_one "''${t%%:*}" "''${t#*:}" || rc=1
        done
      fi

      exit "$rc"
    '';
  };
in
{
  options.qixosTests = {
    enable = lib.mkEnableOption "the in-nube test runner";

    tests = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      default = { };
      description = ''
        Tests this nube declares. Each attribute name must match a program at
        `bin/<name>` in its package, so one name identifies the test in the config, on
        disk and in the runner's report.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ runTests ];
  };
}
