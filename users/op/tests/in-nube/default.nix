# In-nube tests that cover a nube as a whole rather than one module, so they have no
# module to live beside. Counterpart to `admin/`: one file per test, listed here.
{ ... }:
{
  imports = [
    # Declares `qixosTests` and turns the set into `run-tests`.
    ../runner.nix

    ./systemd-has-no-ordering-cycles.nix
    ./systemd-broke-no-cycles-at-boot.nix
  ];
}
