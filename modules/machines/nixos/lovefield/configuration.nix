{ config, pkgs, lib, ... }:
let
  # EC register 0x98 (offset 152) controls cooler boost on MSI GF63 EC 16R3EMS1.101.
  # 0x80 = max fans (cooler boost), 0x02 = firmware auto curve.
  fanControlScript = pkgs.writeShellScript "msi-fan-control" ''
    EC=/sys/kernel/debug/ec/ec0/io
    BOOST_THRESH=65000
    AUTO_THRESH=55000

    set_boost() { printf '\x80' | ${pkgs.coreutils}/bin/dd of="$EC" bs=1 seek=152 count=1 2>/dev/null; }
    set_auto()  { printf '\x02' | ${pkgs.coreutils}/bin/dd of="$EC" bs=1 seek=152 count=1 2>/dev/null; }

    # Locate the coretemp hwmon directory (temp1_input = Package id 0)
    coretemp=""
    for hwmon in /sys/class/hwmon/hwmon*; do
      if [ "$(cat "$hwmon/name" 2>/dev/null)" = "coretemp" ]; then
        coretemp="$hwmon"
        break
      fi
    done

    mode=auto
    while true; do
      temp=$(cat "$coretemp/temp1_input" 2>/dev/null || echo 50000)

      if [ "$temp" -ge "$BOOST_THRESH" ] && [ "$mode" != "boost" ]; then
        set_boost
        mode=boost
      elif [ "$temp" -le "$AUTO_THRESH" ] && [ "$mode" != "auto" ]; then
        set_auto
        mode=auto
      fi

      ${pkgs.coreutils}/bin/sleep 5
    done
  '';
in
{
  imports = [
    ./hardware-configuration.nix
    ./storage.nix                     # ZFS RAIDZ1 pool on the USB DAS
    ../../../services/wireguard       # defines options.services.wireguard-server
    ../../../services/cloudflare-ddns
    ../../../services/caddy           # defines options.services.caddy-server
    ../../../services/hello-world     # Caddy smoke test — remove once real services are up
    ../../../services/syncthing
    ../../../services/sundrop-cafe    # event site + RSVP CSV backend
  ];

  networking.hostName = "lovefield";
  networking.networkmanager.enable = true;
  # TODO: Try setting static IP here

  time.timeZone = "America/Chicago";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS        = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT    = "en_US.UTF-8";
    LC_MONETARY       = "en_US.UTF-8";
    LC_NAME           = "en_US.UTF-8";
    LC_NUMERIC        = "en_US.UTF-8";
    LC_PAPER          = "en_US.UTF-8";
    LC_TELEPHONE      = "en_US.UTF-8";
    LC_TIME           = "en_US.UTF-8";
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelParams = [ "consoleblank=60" ];  # Turn screen off after 60s of inactivity

  # Override _common: password auth required (server is shared)
  services.openssh.openFirewall = true;
  services.openssh.settings.PasswordAuthentication = lib.mkForce true;

  # Laptop-as-server: never sleep, never suspend on lid close
  services.logind.settings.Login.HandleLidSwitch = "ignore";
  services.logind.settings.Login.HandleLidSwitchExternalPower = "ignore";

  # Fan control (MSI GF63) — EC firmware 16R3EMS1.101 unsupported by both
  # in-kernel and BeardOverflow msi-ec. Using ec_sys for direct EC register access.
  # fanControlScript (defined above) monitors CPU Package temp and writes to EC offset 152.
  environment.systemPackages = with pkgs; [
    lm_sensors
    xxd
    gawk
    openssl
    dig
    cloudflared
    config.services.forgejo.package  # same binary forgejo.service runs, for admin CLI use
  ];
  boot.kernelModules = [ "ec_sys" ];
  boot.extraModprobeConfig = "options ec_sys write_support=1";

  systemd.services.msi-fan-control = {
    description = "MSI GF63 temperature-based fan control via EC register";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" "sys-kernel-debug.mount" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = fanControlScript;
      Restart = "always";
      RestartSec = "5s";
    };
  };

  # Battery charge thresholds (MSI GF63)
  services.tlp = {
    enable = true;
    settings = {
      START_CHARGE_THRESH_BAT0 = 40;
      STOP_CHARGE_THRESH_BAT0  = 80;
    };
  };

  services.wireguard-server = {
    enable        = true;
    endpoint      = "vpn.audioboss.win";
    lanInterface  = "enp3s0";
    vpnSubnet     = "10.134.0";
    clients       = [
      # Add client names here and rebuild — keys + QR code appear in
      # /etc/wireguard/clients/<name>/ on the server.
      "renny-zflip-6"
      "renny-xps"
      "renny-macbook"
      "mir-tinyphone"
      "mir-bigphone"
      "mir-macbook"
      "mir-imac"
    ];
  };

  services.hello-world.enable = true;

  services.sundrop-cafe.enable = true;

  # Public exposure via a dashboard-managed Cloudflare Tunnel — no router
  # port-forwarding needed. The tunnel itself (public hostname -> this
  # service) is configured entirely in the Cloudflare Zero Trust dashboard;
  # this just runs the connector with the token it gives you.
  # One-time manual setup: create the tunnel + public hostname in the
  # dashboard, then put the connector token in /etc/cloudflared/sundrop-token.env
  # as TUNNEL_TOKEN=... (chmod 600, not committed) before rebuilding.
  systemd.services.cloudflared-sundrop = {
    description = "Cloudflare Tunnel connector (sundrop, dashboard-managed)";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "network.target" ];
    serviceConfig = {
      Type            = "simple";
      EnvironmentFile = "/etc/cloudflared/sundrop-token.env";
      ExecStart       = "${pkgs.cloudflared}/bin/cloudflared tunnel run";
      Restart         = "always";
      RestartSec      = "5s";
    };
  };

  services.syncthing-users = {
    enable    = true;
    instances = [
      { user = "galac"; guiPort = 8384; }  # will eventually migrate to a different server
      { user = "mir";   guiPort = 8385; }
    ];
  };

  services.cloudflare-dyndns.domains = [
    "audioboss.win"
    "vpn.audioboss.win"
    "hello.audioboss.win"
    # sync-galac and sync-mir intentionally omitted — VPN-only services don't need
    # DDNS updates since VPN clients resolve *.audioboss.win via AdGuard Home (local IP)
    # and WAN clients get 403 from Caddy regardless of what Cloudflare returns.
    "music.audioboss.win"
    # photos.audioboss.win intentionally omitted — Immich is VPN-only (see caddy-server.expose),
    # resolved locally via AdGuard Home's *.audioboss.win rewrite; no public DNS needed.
    "git.audioboss.win"
    "paper.audioboss.win"
    "lovefield.audioboss.win"
  ];

  # AdGuard Home — network-wide DNS resolver with ad blocking.
  # Listens on all interfaces: LAN clients (10.0.0.5:53) and VPN clients (10.134.0.1:53).
  # Returns 10.0.0.5 for *.audioboss.win so both LAN and VPN bypass hairpin NAT.
  # WAN clients use Cloudflare and are unaffected.
  services.adguardhome = {
    enable          = true;
    openFirewall    = true;    # opens port 3000 for the web UI
    mutableSettings = false;  # Allow other users (mir) to change settings via web portal
    settings = {
      users = [
        {
          name     = "admin";
          password = "$2y$05$lhXu9hiy2j1YxpUzYlc5pu42FZ1xLUGwj0kExIhc70ow1sTeAl6YO";
          # pw generated with:
          # htpasswd -nbB admin 'your-chosen-password' | cut -d: -f2
        }
      ];
      dns = {
        # Explicit addresses, not 0.0.0.0 — binding all interfaces claims port 53
        # on every podman bridge gateway too (e.g. 10.89.0.1 for the "immich" network),
        # which stops aardvark-dns (container name resolution) from starting.
        bind_hosts    = [ "10.0.0.5" "10.134.0.1" "127.0.0.1"];
        port          = 53;
        upstream_dns  = [ "1.1.1.1" "1.0.0.1" ];
        bootstrap_dns = [ "1.1.1.1" "1.0.0.1" ];
      };
      # services.adguardhome.settings.filtering.rewrites
      # https://github.com/NixOS/nixpkgs/issues/379646#issuecomment-2638389264
      filtering = {
        rewrites = [
          { domain = "audioboss.win"; answer = "10.0.0.5"; enabled = true;}
          { domain = "*.audioboss.win"; answer = "10.0.0.5"; enabled = true;}
        ];
      };
      # Firefox (and some Chrome configs) default to DNS-over-HTTPS, which bypasses
      # this resolver entirely and breaks *.audioboss.win local rewrites (works in
      # Safari, breaks in Firefox/Chrome — see readme's Known Issues section).
      # Blocking Firefox's canary domain makes it detect a custom DNS setup and
      # auto-disable DoH on this network.
      user_rules = [
        "||use-application-dns.net^"
      ];
    };
  };

  # Port 53 for AdGuard Home DNS (TCP for large responses, UDP for standard queries).
  # lovefield is behind router NAT so opening this globally is safe.
  networking.firewall.allowedTCPPorts = [ 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];

  services.jellyfin.enable = true;
  services.jellyfin.openFirewall = true;  # opens 8096 (HTTP) and 8920 (HTTPS)

  services.navidrome = {
    enable = true;
    openFirewall = true;  # Port 4533
    # Required: navidrome runs chrooted (RootDirectory=/run/navidrome). Without this,
    # /mnt/storage/media/music isn't bind-mounted into the sandbox at all, so any
    # library path under it is "invalid" regardless of Unix permissions.
    settings.MusicFolder = "/mnt/storage/media/music";
  };

  # Immich (self-hosted photo backup), VPN-only.
  # DB secret lives at /etc/immich/db.env (root:root, chmod 600) — placed manually via
  # rsync from the Mac, never committed to this repo. Must contain:
  #   DB_PASSWORD=<random>
  #   POSTGRES_PASSWORD=<same random value>
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  systemd.services.init-immich-network = {
    description = "Create podman network for Immich containers";
    after       = [ "network.target" ];
    wantedBy    = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.podman}/bin/podman network exists immich || \
        ${pkgs.podman}/bin/podman network create immich
    '';
  };

  systemd.tmpfiles.rules = [
    "d /mnt/storage/immich/upload 0755 root root -"
    "d /mnt/storage/immich/postgres 0700 999 999 -"  # immich-app/postgres image runs as uid 999
  ];

  virtualisation.oci-containers.containers = {
    immich-postgres = {
      image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0";
      autoStart = true;
      environment = {
        POSTGRES_USER = "postgres";
        POSTGRES_DB   = "immich";
        POSTGRES_INITDB_ARGS = "--data-checksums";
      };
      environmentFiles = [ "/etc/immich/db.env" ];  # POSTGRES_PASSWORD
      volumes = [ "/mnt/storage/immich/postgres:/var/lib/postgresql/data" ];
      extraOptions = [ "--network=immich" "--shm-size=128mb" ];
    };

    immich-redis = {
      image = "docker.io/valkey/valkey:9";
      autoStart = true;
      extraOptions = [ "--network=immich" ];
    };

    immich-server = {
      image = "ghcr.io/immich-app/immich-server:v3.0.3";  # pin explicit version; check docs.immich.app/install/upgrading before bumping
      autoStart = true;
      environment = {
        DB_HOSTNAME    = "immich-postgres";
        DB_USERNAME    = "postgres";
        DB_DATABASE_NAME = "immich";
        REDIS_HOSTNAME = "immich-redis";
      };
      environmentFiles = [ "/etc/immich/db.env" ];  # DB_PASSWORD
      volumes = [
        "/mnt/storage/immich/upload:/data"
        "/etc/localtime:/etc/localtime:ro"
      ];
      ports = [ "127.0.0.1:2283:2283" ];  # loopback only — Caddy is the only consumer
      extraOptions = [ "--network=immich" ];
      dependsOn = [ "immich-postgres" "immich-redis" ];
    };
  };

  # Forgejo (self-hosted git forge), bare-bones: sqlite3 db, no mailer,
  # no Actions (CI) — just repos + LFS. Registration is closed since this
  # is reachable from the open internet; create accounts manually with
  #   sudo -u forgejo forgejo admin user create --username <name> --email <email> --password '<pw>' --admin
  # (drop --admin for non-admin accounts). Forgejo's own SSH server is
  # disabled to avoid fighting with the system OpenSSH on port 22 — clone
  # over HTTPS (https://git.audioboss.win/<user>/<repo>.git) for now.
  services.forgejo = {
    enable = true;
    lfs.enable = true;
    settings = {
      server = {
        DOMAIN     = "git.audioboss.win";
        ROOT_URL   = "https://git.audioboss.win/";
        HTTP_ADDR  = "127.0.0.1";  # Caddy is the only consumer, same pattern as Immich
        HTTP_PORT  = 3000;
        DISABLE_SSH = true;
      };
      service.DISABLE_REGISTRATION = true;
      mailer.ENABLED = false;
    };
  };

  services.caddy-server = {
    enable    = true;
    domain    = "audioboss.win";
    email     = "outpost-admin@proton.me";
    vpnSubnet = "10.134.0.0/24";
    expose = [
      { subdomain = "sync-galac"; port = 8384; }  # Syncthing (galac)
      { subdomain = "sync-mir";   port = 8385; }  # Syncthing (mir)
      { subdomain = "media";      port = 8096; }                   # Jellyfin (caddy sanity check)
      { subdomain = "dns";        port = 3000; }
      { subdomain = "photos";     port = 2283; }  # Immich
      { subdomain = "music";      port = 4533; }   # Navidrome
      # { subdomain = "docs";    port = 28981; }  # Paperless
      { subdomain = "git";       port = 3000; }   # Forgejo
    ];
  };

  users.users.galac = {
    isNormalUser = true;
    description  = "galac";
    extraGroups  = [ "networkmanager" "wheel" ];
    shell        = pkgs.zsh;
  };

  users.users.mir = {
    isNormalUser = true;
    description  = "mir";
    extraGroups  = [ "networkmanager" "wheel" ];
    shell        = pkgs.zsh;
    # Password is locked until set manually: sudo passwd mir
  };

  system.stateVersion = "26.05";

  home-manager.users.galac.programs.zsh.shellAliases.rebuild =
    "cd /etc/nixos; sudo git pull; sudo nixos-rebuild switch --flake .#lovefield";
}
