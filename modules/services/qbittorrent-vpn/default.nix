{ config, pkgs, lib, ... }:
let
  cfg = config.services.qbittorrent-vpn;
  ns  = config.services.wireguard-netns.namespace;
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
      default     = "/mnt/storage/media/downloads";
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

    environment.systemPackages = [ pkgs.qbittorrent-nox ];
  };
}
