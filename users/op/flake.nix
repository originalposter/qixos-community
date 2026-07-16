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
         then importNixFiles (dir + "/${n}")
         else import (dir + "/${n}"))) nixFiles;
  in {
    nixosModules = {
      modules = importNixFiles ./modules;
      nubes = importNixFiles ./nubes;
      outer-configs = importNixFiles ./outer-configs;
    };
  };
}
