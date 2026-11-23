# A netvm that sends the qubes behind it through Mullvad, with the Mullvad app's daemon.
# The nube needs `providesNetwork = true` in the outer config, and the qubes it serves
# name it as their netvm.
#
# Log in once, with the GUI or `mullvad account login`.
{ pkgs, config, ... }:
let
  # The daemon's WireGuard interface, kernel or userspace.
  tunnel = "wg0-mullvad";

  # The resolver Mullvad runs inside the tunnel, the one its app uses unless told to use
  # another.
  tunnelDns = "10.64.0.1";

  # Downstream qubes come in on interfaces in group 2.
  #
  # forward: the kill switch. Nothing from them leaves except through the tunnel, or to
  # another downstream, which qubes' own rules decide. Mullvad's firewall cannot do this:
  # the daemon removes its table when disconnected without lockdown mode, as it is with
  # no account, and when it exits cleanly.
  #
  # dns: their lookups go to the tunnel's resolver, the only one Mullvad lets through
  # the tunnel. Ahead of qubes' own redirect, since the first NAT rule to match wins.
  # With the tunnel down the forward chain drops them. A DNS server chosen in the app is
  # not followed, and IPv6 lookups are not redirected: both fail rather than leak.
  #
  # A downstream whose qvm-firewall allows DNS only by the `dns` special target loses it
  # here: the target is matched against this netvm's resolv.conf, after the redirect.
  # It needs the resolver allowed by address:
  #
  #   qvm-firewall <qube> add --before 0 accept dsthost=10.64.0.1
  #
  # Replaced in one transaction, so a reload never leaves a moment without it.
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

  # This netvm's own lookups. The daemon writes the tunnel's resolver into resolv.conf,
  # which resolved here does not read, and resolved's only servers are qubes' on eth0,
  # which Mullvad's firewall rejects while connected. As a global server it is asked
  # alongside them, and answers through the tunnel.
  services.resolved.settings.Resolve.DNS = [ tunnelDns ];

  # In /rw, not /etc/mullvad-vpn on the root volume: a login forgotten at every reboot
  # registers a new device each time, and an account takes only a few.
  systemd.services.mullvad-daemon = {
    environment.MULLVAD_SETTINGS_DIR = "/rw/qixos/mullvad-vpn";
    # The daemon creates only the last component of that path, and exits if the parent
    # is missing, which it is on a nube with nothing else in /rw/qixos.
    preStart = "mkdir -p /rw/qixos";
    after = [ "qubes-mount-dirs.service" ];
    requires = [ "qubes-mount-dirs.service" ];
  };

  # Turn on local network sharing, so this netvm's ICMP errors reach the qubes behind it.
  # Without it the daemon's output chain drops "fragmentation needed" on its way to a downstream,
  # which then keeps resending packets too big for the tunnel: pings and lookups work,
  # TLS handshakes and QUIC stall. With multihop the tunnel's MTU is small enough to hit
  # that on every page. It also lets this netvm itself reach private networks outside
  # the tunnel; the qubes behind it still cannot, since the kill switch passes them only
  # to the tunnel. Set again at every boot, so turning it off in the app does not stick.
  systemd.services.mullvad-netvm-lan = {
    description = "Let the netvm's ICMP errors reach the qubes behind it";
    wantedBy = [ "multi-user.target" ];
    requires = [ "mullvad-daemon.service" ];
    after = [ "mullvad-daemon.service" ];
    path = [ config.services.mullvad-vpn.package ];
    serviceConfig.Type = "oneshot";
    # The daemon's socket comes up a moment after the daemon starts.
    script = ''
      for i in $(seq 30); do
        mullvad lan set allow && exit 0
        sleep 1
      done
      exit 1
    '';
  };

  # Loaded by qixos core's forwarding gate every time it opens, so forwarding never
  # starts without it: a failed load leaves the gate shut. Not a unit of its own: the
  # gate's start is queued at boot under the template's units, before any requirement
  # added here exists, and runs after the AppVM switch with this.
  systemd.services.qixos-forwarding-gate.preStart = "${pkgs.nftables}/bin/nft -f ${rules}";

  # Without core's gate the line above makes a unit with nothing to run, and the kill
  # switch is never loaded.
  assertions = [{
    assertion = config.systemd.services.qixos-forwarding-gate.serviceConfig ? ExecStart;
    message = "blueprints.mullvad-netvm needs a qixos core with network nubes, whose forwarding gate loads its kill switch";
  }];

  # nft on the path, for reading this netvm's rules.
  environment.systemPackages = [ pkgs.nftables ];
}
