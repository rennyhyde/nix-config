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
    enable       = true;
    endpoint     = "vpn.audioboss.win";
    lanInterface = "enp3s0";
    vpnSubnet    = "10.134.0";
    clients      = [
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
    "sync-galac.audioboss.win"
    "sync-mir.audioboss.win"
    "music.audioboss.win"
    "photos.audioboss.win"
    "git.audioboss.win"
    "paper.audioboss.win"
    "lovefield.audioboss.win"
  ];

  services.caddy-server = {
    enable    = true;
    domain    = "audioboss.win";
    email     = "outpost-admin@proton.me";
    vpnSubnet = "10.134.0.0/24";
    expose = [
      { subdomain = "sync-galac"; port = 8384; vpnOnly = true; }  # Syncthing (galac)
      { subdomain = "sync-mir";   port = 8385; vpnOnly = true; }  # Syncthing (mir)
      # { subdomain = "music";   port = 4533; }   # Navidrome
      # { subdomain = "photos";  port = 2283; }   # Immich
      # { subdomain = "media";   port = 8096; }   # Jellyfin
      # { subdomain = "docs";    port = 28981; }  # Paperless
      # { subdomain = "git";     port = 3000; }   # Forgejo
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
}
