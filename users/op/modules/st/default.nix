{ lib, pkgs, config, ... }:
let
  cfg = config.qixos-st;
  stConfig = pkgs.writeText "config.h" (builtins.readFile ./config.h);
in
{
  options.qixos-st = {
    enable = lib.mkEnableOption "enable suckless terminal";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.st.overrideAttrs (oldAttrs: {
        src = pkgs.fetchFromGitHub {
          owner = "LukeSmithxyz";
          repo = "st";
          rev = "62ebf677d3ad79e0596ff610127df5db034cd234";
          sha256 = "sha256-L4FKnK4k2oImuRxlapQckydpAAyivwASeJixTj+iFrM=";
        };
        buildInputs = oldAttrs.buildInputs ++ [ pkgs.harfbuzz ];
        postPatch = (oldAttrs.postPatch or "") + ''
          cp ${stConfig} config.h
        '';
        postInstall = (oldAttrs.postInstall or "") + ''
          mkdir -p $out/share/applications
          cat > $out/share/applications/st.desktop <<EOF
          [Desktop Entry]
          Name=st
          Exec=$out/bin/st
          Type=Application
          Categories=System;TerminalEmulator;
          Terminal=false
          EOF
        '';
      }))
    ];
  };
}
