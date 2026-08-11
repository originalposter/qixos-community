# Shared configuration for a qixos management qube, used by both the production
# admin and the test admin.
#
# A function of qixCore rather than a plain module: the admin tools live in
# qixCore.packages, which is built with `overlays.admin`. The overlay applied to
# nubes is `overlays.base`, and that does not carry qixos-rebuild or
# qubes-core-admin-client, so they cannot be reached through `pkgs` from inside a
# module. Call it from a flake's outputs:
#
#   (opQixCommunity.nixosModules.modules.blueprints.qixos-admin { inherit qixCore; })
#
{ qixCore }:
{ pkgs, ... }:
{
  environment.systemPackages = [
    qixCore.packages.${pkgs.stdenv.hostPlatform.system}.qubes-core-admin-client
    qixCore.packages.${pkgs.stdenv.hostPlatform.system}.qixos-rebuild
    # A hack to keep the qubes admin `clone_vm` from erroring on a missing
    # qvm-appmenus.
    qixCore.packages.${pkgs.stdenv.hostPlatform.system}.qvm-appmenus-stub
  ];
}
