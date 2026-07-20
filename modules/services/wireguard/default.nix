{ config, pkgs, lib, ... }:
let
  cfg = config.services.wireguard-server;

  # Runs at activation time (before services start) to provision server keys
  # and any new client key pairs. Idempotent — skips existing keys.
  provisionScript = pkgs.writeShellScript "wireguard-provision" ''
    set -euo pipefail
    WG_DIR=/etc/wireguard

    mkdir -p $WG_DIR
    chmod 700 $WG_DIR

    # ── server keys ──────────────────────────────────────────────────────────
    if [ ! -f $WG_DIR/private.key ]; then
      ${pkgs.wireguard-tools}/bin/wg genkey \
        | tee $WG_DIR/private.key \
        | ${pkgs.wireguard-tools}/bin/wg pubkey > $WG_DIR/public.key
      chmod 600 $WG_DIR/private.key
      echo "wireguard: generated server keys"
    fi
    SERVER_PUBKEY=$(cat $WG_DIR/public.key)

    # ── client provisioning ──────────────────────────────────────────────────
    mkdir -p $WG_DIR/clients

    ${lib.concatMapStringsSep "\n" (name: ''
      (
        DIR=$WG_DIR/clients/${name}
        mkdir -p $DIR

        if [ ! -f $DIR/private.key ]; then
          ${pkgs.wireguard-tools}/bin/wg genkey \
            | tee $DIR/private.key \
            | ${pkgs.wireguard-tools}/bin/wg pubkey > $DIR/public.key
          chmod 600 $DIR/private.key

          # Find next available IP (.2–.254), skipping any already in client configs
          CLIENT_IP=""
          for suffix in $(seq 2 254); do
            CANDIDATE="${cfg.vpnSubnet}.$suffix"
            IN_USE=false
            for conf in $WG_DIR/clients/*/client.conf; do
              if [ -f "$conf" ] && grep -q "^Address = $CANDIDATE/" "$conf"; then
                IN_USE=true
                break
              fi
            done
            if [ "$IN_USE" = false ]; then
              CLIENT_IP=$CANDIDATE
              break
            fi
          done

          PRIV=$(cat $DIR/private.key)

          {
            echo '[Interface]'
            echo "PrivateKey = $PRIV"
            echo "Address = $CLIENT_IP/24"
            echo "DNS = ${cfg.vpnSubnet}.1"
            echo ""
            echo '[Peer]'
            echo "PublicKey = $SERVER_PUBKEY"
            echo 'Endpoint = ${cfg.endpoint}:${toString cfg.listenPort}'
            echo 'AllowedIPs = 0.0.0.0/0'
            echo 'PersistentKeepalive = 25'
          } > $DIR/client.conf

          echo "$CLIENT_IP" > $DIR/ip
          ${pkgs.qrencode}/bin/qrencode -t ansiutf8 -o $DIR/qr.txt < $DIR/client.conf
          echo "wireguard: provisioned client ${name} → $CLIENT_IP"
          echo "  QR code: cat $DIR/qr.txt"
        fi

        # Migrate: create ip file for clients provisioned before this was added
        if [ -f $DIR/client.conf ] && [ ! -f $DIR/ip ]; then
          grep "^Address" $DIR/client.conf | cut -d' ' -f3 | cut -d/ -f1 > $DIR/ip
        fi

        # Migrate: switch DNS from public resolver to this server's VPN resolver
        # so clients resolve domain names directly through the tunnel.
        if grep -q "^DNS = 1.1.1.1$" "$DIR/client.conf" 2>/dev/null; then
          sed -i "s/^DNS = 1.1.1.1$/DNS = ${cfg.vpnSubnet}.1/" "$DIR/client.conf"
          ${pkgs.qrencode}/bin/qrencode -t ansiutf8 -o $DIR/qr.txt < $DIR/client.conf
          echo "wireguard: updated DNS for ${name} -> ${cfg.vpnSubnet}.1 (re-scan QR code)"
        fi
      )
    '') cfg.clients}
  '';
in
{
  options.services.wireguard-server = {
    enable = lib.mkEnableOption "WireGuard VPN server with auto-provisioned clients";

    endpoint = lib.mkOption {
      type        = lib.types.str;
      example     = "vpn.example.com";
      description = "Public hostname clients use to reach this server (no port).";
    };

    listenPort = lib.mkOption {
      type    = lib.types.port;
      default = 51820;
    };

    lanInterface = lib.mkOption {
      type        = lib.types.str;
      example     = "enp3s0";
      description = "LAN-facing interface for NAT masquerade.";
    };

    vpnSubnet = lib.mkOption {
      type        = lib.types.str;
      default     = "10.100.0";
      description = "First three octets of the VPN subnet; server gets .1, clients .2+.";
    };

    clients = lib.mkOption {
      type    = lib.types.listOf lib.types.str;
      default = [];
      example = [ "android" "macbook" ];
      description = ''
        Client names to auto-provision. On rebuild, new names get a key pair,
        config, and QR code under /etc/wireguard/clients/<name>/.
        Removing a name revokes peer access; files are kept for reference.
      '';
    };

    localDomains = lib.mkOption {
      type    = lib.types.listOf lib.types.str;
      default = [];
      example = [ "example.com" ];
      description = ''
        Domains to resolve to this server's VPN IP (vpnSubnet.1) for VPN clients.
        Enables a dnsmasq resolver on wg0 so clients bypass hairpin NAT when
        accessing services hosted on this server.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Provision keys before any services start
    system.activationScripts.wireguard-provision = "${provisionScript}";

    networking.wg-quick.interfaces.wg0 = {
      address        = [ "${cfg.vpnSubnet}.1/24" ];
      listenPort     = cfg.listenPort;
      privateKeyFile = "/etc/wireguard/private.key";

      # Per-client peer blocks — changing the clients list changes this string,
      # which changes the systemd unit and triggers a service restart on rebuild.
      postUp = ''
        ${lib.concatMapStringsSep "\n" (name: ''
          if [ -f /etc/wireguard/clients/${name}/ip ] && [ -f /etc/wireguard/clients/${name}/public.key ]; then
            read -r PEER_IP     < /etc/wireguard/clients/${name}/ip
            read -r PEER_PUBKEY < /etc/wireguard/clients/${name}/public.key
            ${pkgs.wireguard-tools}/bin/wg set wg0 \
              peer "$PEER_PUBKEY" \
              allowed-ips "$PEER_IP/32"
          fi
        '') cfg.clients}
        ${pkgs.iptables}/bin/iptables -A FORWARD -i wg0 -j ACCEPT
        ${pkgs.iptables}/bin/iptables -A FORWARD -o wg0 -j ACCEPT
        ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -o ${cfg.lanInterface} -j MASQUERADE
      '';

      preDown = ''
        ${pkgs.iptables}/bin/iptables -D FORWARD -i wg0 -j ACCEPT
        ${pkgs.iptables}/bin/iptables -D FORWARD -o wg0 -j ACCEPT
        ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -o ${cfg.lanInterface} -j MASQUERADE
      '';
    };

    networking.firewall.allowedUDPPorts = [ cfg.listenPort ];
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    environment.systemPackages = with pkgs; [ wireguard-tools qrencode ];

    # DNS resolver for VPN clients — returns vpnSubnet.1 for localDomains,
    # forwards everything else to 1.1.1.1. Listens only on wg0 so it's
    # never reachable from the internet.
    services.dnsmasq = lib.mkIf (cfg.localDomains != []) {
      enable = true;
      resolveLocalQueries = false;
      extraConfig = ''
        interface=wg0
        bind-interfaces
        no-resolv
        server=1.1.1.1
        server=1.0.0.1
        ${lib.concatMapStringsSep "\n" (d: "address=/${d}/${cfg.vpnSubnet}.1") cfg.localDomains}
      '';
    };

    networking.firewall.interfaces.wg0 = lib.mkIf (cfg.localDomains != []) {
      allowedUDPPorts = [ 53 ];
    };
  };
}
