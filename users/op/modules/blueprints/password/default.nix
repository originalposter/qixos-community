# Password vault nube: a `pass` store, and the menu that hands a credential to another
# qube. See ../../password/menu.nix for the dom0 policy this needs.
{ pkgs, ... }:
{
  imports = [ ../../password-menu/menu.nix ];

  qubesPasswordMenu.enable = true;

  environment.systemPackages = with pkgs; [ gnupg pass keepassxc rofi ];

  programs.gnupg.agent = {
    enable = true;
    # Graphical rather than curses: the menu is launched from a dom0 keybind, which has
    # no tty for a curses pinentry to draw in, so `pass show` would fail there with no
    # visible prompt.
    #
    # qt rather than gnome3, which drives GCR's prompter over D-Bus and has nothing to
    # talk to in a session this bare.
    pinentryPackage = pkgs.pinentry-qt;
  };
}
