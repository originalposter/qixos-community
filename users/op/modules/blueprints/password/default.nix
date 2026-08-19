{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [ gnupg pass keepassxc ];

  programs.gnupg.agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-curses;
  };
}
