{ pkgs, ... }:
{
  # WireGuard VPN server (raw wg-quick).
  #
  # One-time setup on the machine before rebuilding:
  #   wg genkey | sudo tee /etc/wireguard/private.key | wg pubkey | sudo tee /etc/wireguard/public.key
  #   sudo chmod 600 /etc/wireguard/private.key
  #
  # Router: forward UDP 51820 → this machine's LAN IP.
  # For each client: generate a key pair, add the public key to peers below, rebuild.
  # Client AllowedIPs = 192.168.1.0/24,10.100.0.0/24 for split tunnel (home network only).

  networking.wg-quick.interfaces.wg0 = {
    address    = [ "10.100.0.1/24" ];
    listenPort = 51820;
    privateKeyFile = "/etc/wireguard/private.key";

    # NAT: VPN clients can reach the LAN through lovefield's ethernet interface.
    # Replace enp3s0 with the LAN interface name if it ever changes.
    postUp = ''
      ${pkgs.iptables}/bin/iptables -A FORWARD -i wg0 -j ACCEPT
      ${pkgs.iptables}/bin/iptables -A FORWARD -o wg0 -j ACCEPT
      ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -o enp3s0 -j MASQUERADE
    '';
    preDown = ''
      ${pkgs.iptables}/bin/iptables -D FORWARD -i wg0 -j ACCEPT
      ${pkgs.iptables}/bin/iptables -D FORWARD -o wg0 -j ACCEPT
      ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -o enp3s0 -j MASQUERADE
    '';

    peers = [
      # Example — add one block per client:
      # {
      #   publicKey  = "BASE64_CLIENT_PUBLIC_KEY=";
      #   allowedIPs = [ "10.100.0.2/32" ];  # unique VPN IP per client
      # }
    ];
  };

  networking.firewall.allowedUDPPorts = [ 51820 ];
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
}
