# A netvm that sends the qubes behind it through Mullvad, with the Mullvad app's daemon.
# The nube needs `providesNetwork = true` in the outer config, and the qubes it serves
# name it as their netvm.
#
# Log in once, with the GUI or `mullvad account login`.
{ pkgs, config, ... }:
let
  # The daemon's WireGuard interface, kernel or userspace (talpid-wireguard's
  # MULLVAD_INTERFACE_NAME).
  tunnel = "wg0-mullvad";

  # The resolver Mullvad runs inside the tunnel, the one its app uses unless told to use
  # another.
  tunnelDns = "10.64.0.1";

  # Downstream qubes come in on interfaces in group 2, set by vif-route-qubes.
  #
  # forward: nothing from them leaves except through the tunnel. Mullvad's own firewall
  # cannot be the kill switch here. The daemon removes its table whenever it is
  # disconnected without lockdown mode, which is also its state with no account, and
  # whenever it exits cleanly; in any of those a netvm with forwarding on would carry
  # its downstreams out of sys-net in the clear. This table does not depend on the
  # daemon at all. Traffic to another downstream (group 2 again) never leaves the
  # machine, so it is left to qubes' own rules, which drop it unless a custom-forward
  # rule allows it, as on stock Qubes.
  #
  # dns: their lookups go to the tunnel's resolver. Qubes points them at 10.139.1.1 and
  # .2, which qubes-setup-dnat-to-ns redirects to this netvm's upstream resolvers, read
  # once when the uplink comes up and never again when the tunnel does; and Mullvad's
  # firewall rejects DNS through the tunnel to anything but its own resolver. A
  # higher-priority DNAT wins, since the first NAT rule to match a connection settles
  # it. With the tunnel down, the redirected lookup is just more downstream traffic,
  # and the forward chain drops it. A DNS server chosen in the app (a content blocker,
  # say) is not followed: Mullvad then rejects this one, and downstream lookups fail
  # rather than leak. IPv6 lookups are not redirected and fail the same way.
  #
  # The daemon does not manage DNS through resolved here: talpid uses resolved only when
  # /etc/resolv.conf is resolved's stub, and in a nube it is qubes' own file. What it
  # falls back to touches this netvm's own lookups, not where downstream ones go.
  #
  # A downstream whose qvm-firewall drops by default and lets DNS through by the `dns`
  # special target loses DNS here. The firewall daemon matches that target against this
  # netvm's /etc/resolv.conf, which lists the qubes nameservers, and sees the lookup
  # after the redirect, addressed to the tunnel's resolver. On stock Qubes the two agree,
  # since the redirect goes to resolv.conf's servers. Such a qube needs the resolver
  # allowed by address, for TCP as well as UDP since resolvers retry a truncated answer
  # over TCP:
  #
  #   qvm-firewall <qube> add --before 0 accept dsthost=10.64.0.1
  #
  # Replacing the table in one transaction, so reloading it never leaves a moment
  # without it.
  rules = pkgs.writeText "mullvad-netvm.nft" ''
    table inet mullvad-netvm
    delete table inet mullvad-netvm
    table inet mullvad-netvm {
      chain forward {
        type filter hook forward priority filter - 5; policy accept;
        iifgroup 2 oifgroup != 2 oifname != "${tunnel}" counter drop
      }
      chain dns {
        type nat hook prerouting priority dstnat - 5; policy accept;
        iifgroup 2 meta nfproto ipv4 meta l4proto { tcp, udp } th dport 53 counter dnat ip to ${tunnelDns}
      }
    }
  '';
in
{
  services.mullvad-vpn = {
    enable = true;
    # A setuid wrapper that runs a command outside the tunnel. Nothing in a netvm needs it.
    enableExcludeWrapper = false;
  };

  # The daemon keeps its account, device and settings in /etc/mullvad-vpn by default,
  # which is on the root volume and so gone on every reboot of an AppVM. Each fresh login
  # registers a new device on the account, and an account takes only a few, so a nube
  # that forgot its login would soon be refused. /rw is the volume that persists.
  systemd.services.mullvad-daemon = {
    environment.MULLVAD_SETTINGS_DIR = "/rw/qixos/mullvad-vpn";
    after = [ "qubes-mount-dirs.service" ];
    requires = [ "qubes-mount-dirs.service" ];
  };

  # Loaded by qixos core's forwarding gate itself, every time it opens, and the gate stays
  # shut if the load fails. The gate opens only after the AppVM switch, so the template's
  # configuration, which has none of this, never forwards; and a table deleted by hand is
  # back before forwarding next resumes. At boot the gate's start is queued before the
  # switch, under the template's units, and runs after it with these.
  #
  # Tried first as a unit of its own, requiredBy and before the gate. That held at boot
  # only through the switch failing, since a queued job keeps the requirements it was
  # queued with, and a later opening was covered only by the unit still being active,
  # whether or not its table was still there.
  systemd.services.qixos-forwarding-gate.preStart = "${pkgs.nftables}/bin/nft -f ${rules}";

  # Without core's gate the line above defines a unit of its own with nothing to run, and
  # the kill switch is silently never loaded.
  assertions = [{
    assertion = config.systemd.services.qixos-forwarding-gate.serviceConfig ? ExecStart;
    message = "blueprints.mullvad-netvm needs a qixos core with network nubes, whose forwarding gate loads its kill switch";
  }];

  # nft on the path, for reading this netvm's rules.
  environment.systemPackages = [ pkgs.nftables ];
}
