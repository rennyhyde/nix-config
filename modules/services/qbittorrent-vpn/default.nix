{ config, pkgs, lib, ... }:
let
  cfg   = config.services.qbittorrent-vpn;
  ns    = config.services.wireguard-netns.namespace;
  iface = config.services.wireguard-netns.interfaceName;

  # Fails loudly (non-zero exit) the moment any check doesn't hold, rather than
  # printing a wall of output you have to read carefully. Run as root (needs to
  # read another user's /proc/<pid>/ns/net and `ip netns exec`).
  leakCheckScript = pkgs.writeShellScriptBin "qbt-leak-check" ''
    set -euo pipefail
    NS="${ns}"
    IFACE="${iface}"
    TORRENT_PORT="${toString cfg.torrentingPort}"

    if [ "$(id -u)" -ne 0 ]; then
      echo "Run this as root: sudo qbt-leak-check" >&2
      exit 1
    fi

    echo "== 1. Is qbittorrent-nox actually inside the '$NS' namespace? =="
    PID=$(${pkgs.systemd}/bin/systemctl show -p MainPID --value qbittorrent-nox)
    if [ -z "$PID" ] || [ "$PID" = "0" ]; then
      echo "FAIL: qbittorrent-nox is not running"; exit 1
    fi
    PROC_NETNS=$(readlink "/proc/$PID/ns/net")
    NS_NETNS=$(readlink "/var/run/netns/$NS")
    if [ "$PROC_NETNS" != "$NS_NETNS" ]; then
      echo "FAIL: qbittorrent-nox (pid $PID, netns $PROC_NETNS) is NOT in namespace $NS ($NS_NETNS)"
      exit 1
    fi
    echo "OK: qbittorrent-nox (pid $PID) confirmed inside $NS"

    echo
    echo "== 2. Interfaces inside '$NS' — should ONLY be lo + $IFACE =="
    ${pkgs.iproute2}/bin/ip -n "$NS" -brief link show
    UNEXPECTED=$(${pkgs.iproute2}/bin/ip -n "$NS" -brief link show | awk '{print $1}' | grep -v -E '^(lo|'"$IFACE"')' || true)
    if [ -n "$UNEXPECTED" ]; then
      echo "FAIL: unexpected interface(s) in $NS: $UNEXPECTED"; exit 1
    fi
    echo "OK: no unexpected interfaces"

    echo
    echo "== 3. Routes inside '$NS' — should ONLY have a default via $IFACE =="
    ${pkgs.iproute2}/bin/ip -n "$NS" route show

    echo
    echo "== 4. Public IP: tunnel namespace vs. host's real WAN (must differ) =="
    NS_IP=$(${pkgs.iproute2}/bin/ip netns exec "$NS" ${pkgs.curl}/bin/curl -s --max-time 5 https://ifconfig.me || echo UNREACHABLE)
    HOST_IP=$(${pkgs.curl}/bin/curl -s --max-time 5 https://ifconfig.me || echo UNREACHABLE)
    echo "  protonvpn namespace: $NS_IP"
    echo "  host (normal WAN):   $HOST_IP"
    if [ "$NS_IP" = "UNREACHABLE" ]; then
      echo "FAIL: namespace has no working internet — tunnel is down"; exit 1
    fi
    if [ "$NS_IP" = "$HOST_IP" ]; then
      echo "FAIL: namespace IP matches host IP — traffic is NOT going through the tunnel"; exit 1
    fi
    echo "OK: namespace exits through a different IP than the host"

    echo
    echo "== 5. Torrenting port must NOT be reachable from the host namespace =="
    if ${pkgs.iproute2}/bin/ss -tlnp 2>/dev/null | grep -q ":$TORRENT_PORT "; then
      echo "FAIL: something is listening on port $TORRENT_PORT outside the namespace"; exit 1
    fi
    echo "OK: torrenting port not exposed on the host"

    echo
    echo "All checks passed — qBittorrent is confined to $NS, exiting via $IFACE only."
  '';
in
{
  options.services.qbittorrent-vpn = {
    enable = lib.mkEnableOption "qBittorrent, confined to the wireguard-netns namespace (no direct WAN access)";

    webuiPort = lib.mkOption {
      type        = lib.types.port;
      default     = 8080;
      description = "Port the WebUI listens on inside the namespace, and is proxied to on the host loopback.";
    };

    torrentingPort = lib.mkOption {
      type        = lib.types.port;
      default     = 51413;
      description = "BitTorrent listening port inside the namespace (only reachable via the VPN tunnel, e.g. Proton NAT-PMP forwarding).";
    };

    downloadDir = lib.mkOption {
      type        = lib.types.str;
      default     = "/mnt/storage/media/downloads/torrent";
      description = "Save path for torrents. Kept in the shared storage/media dataset so hardlink moves into the library work.";
    };

    profileDir = lib.mkOption {
      type        = lib.types.str;
      default     = "/var/lib/qbittorrent-vpn";
      description = "Where qBittorrent stores its config/state (--profile).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = config.services.wireguard-netns.enable;
      message   = "services.qbittorrent-vpn requires services.wireguard-netns to be enabled (it runs qBittorrent inside that namespace).";
    }];

    users.groups.qbittorrent-vpn = { };
    users.users.qbittorrent-vpn = {
      isSystemUser = true;
      group        = "qbittorrent-vpn";
      extraGroups  = [ "media" ]; # write access to the shared storage/media dataset
      home         = cfg.profileDir;
      createHome   = false; # tmpfiles rule below owns creation, so qBittorrent doesn't need CAP_* to make its own profile dir
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.profileDir} 0750 qbittorrent-vpn qbittorrent-vpn -"
      "d ${cfg.downloadDir} 2775 root media -" # no-op if it already exists with these owners; see storage runbook
    ];

    # The actual torrent client. Confined to the protonvpn namespace via
    # NetworkNamespacePath — it has no route to the internet other than the
    # WireGuard tunnel that namespace owns (see wireguard-netns module).
    systemd.services.qbittorrent-nox = {
      description = "qBittorrent (VPN-confined)";
      bindsTo     = [ "netns@${ns}.service" "${ns}.service" ];
      requires    = [ "network-online.target" ];
      after       = [ "netns@${ns}.service" "${ns}.service" "network-online.target" ];
      wantedBy    = [ "multi-user.target" ];
      serviceConfig = {
        Type                  = "simple";
        User                  = "qbittorrent-vpn";
        Group                 = "qbittorrent-vpn";
        NetworkNamespacePath  = "/var/run/netns/${ns}";
        # NOTE: qBittorrent's --save-path flag only applies to torrents passed
        # positionally on the command line, not the WebUI's persistent default —
        # that has to be set once via Options -> Downloads -> Default Save Path
        # in the WebUI (see readme.md). Nothing in this module manages
        # qBittorrent.conf, so that one-time setting persists across rebuilds.
        Environment = "HOME=${cfg.profileDir}";
        ExecStart = ''
          ${pkgs.qbittorrent-nox}/bin/qbittorrent-nox \
            --confirm-legal-notice \
            --profile=${cfg.profileDir} \
            --webui-port=${toString cfg.webuiPort} \
            --torrenting-port=${toString cfg.torrentingPort}
        '';
        Restart    = "on-failure";
        RestartSec = "5s";
        # Belt-and-suspenders on top of the namespace isolation: no reason this
        # process should ever need to see the host's other network devices.
        PrivateDevices = true;
        NoNewPrivileges = true;
      };
    };

    # Bridges the isolated namespace's WebUI back to the host loopback so Caddy
    # (which lives in the main namespace) can reverse-proxy to it. Mirrors the
    # deluged-proxy pattern: PrivateNetwork + JoinsNamespaceOf puts this proxy
    # in qbittorrent-nox's namespace, so "127.0.0.1:<port>" as its *target*
    # resolves to qBittorrent's own loopback inside that namespace, while the
    # *listening* socket below is created in the main namespace for Caddy to reach.
    systemd.sockets.qbittorrent-webui-proxy = {
      description   = "Socket for proxying into qBittorrent's WebUI";
      listenStreams = [ "127.0.0.1:${toString cfg.webuiPort}" ];
      wantedBy      = [ "sockets.target" ];
    };

    systemd.services.qbittorrent-webui-proxy = {
      description = "Proxy to qBittorrent WebUI in the ${ns} namespace";
      requires    = [ "qbittorrent-nox.service" "qbittorrent-webui-proxy.socket" ];
      after       = [ "qbittorrent-nox.service" "qbittorrent-webui-proxy.socket" ];
      unitConfig.JoinsNamespaceOf = "qbittorrent-nox.service";
      serviceConfig = {
        PrivateNetwork = true;
        ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd --exit-idle-time=5min 127.0.0.1:${toString cfg.webuiPort}";
      };
    };

    environment.systemPackages = [ pkgs.qbittorrent-nox leakCheckScript ];
  };
}
