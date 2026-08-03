{
  description = ''
  Here I've put all of my stuff as flake in case I want to use it inside nix.
  '';

  inputs.nixpkgs.url = "nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs, ... }: 
  let
    lib = nixpkgs.lib;
    importNixFiles = dir:
      let
        entries = builtins.readDir dir;
        nixFiles = lib.filterAttrs (n: t:
          (t == "regular" && lib.hasSuffix ".nix" n && n != "default.nix")
          || t == "directory"
        ) entries;
      in
      lib.mapAttrs' (n: t: lib.nameValuePair
        (lib.removeSuffix ".nix" n)
        (if t == "directory"
         # A directory holding a default.nix *is* the thing, so import the
         # directory. Recursing into it instead would drop the default.nix,
         # since the filter above excludes it, and leave an empty attrset --
         # which is a valid no-op NixOS module, so the mistake stays silent.
         then (if builtins.pathExists (dir + "/${n}/default.nix")
               then import (dir + "/${n}")
               else importNixFiles (dir + "/${n}"))
         else import (dir + "/${n}"))) nixFiles;
  in {
    nixosModules = {
      modules = importNixFiles ./modules;
      nubes = importNixFiles ./nubes;
      outer-configs = importNixFiles ./outer-configs;
    };
  };
}
