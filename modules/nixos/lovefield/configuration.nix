{ config, pkgs, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "lovefield";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Static IP — update interface name to match your hardware (check with `ip link`)
  # networking.interfaces.eth0.ipv4.addresses = [{
  #   address = "192.168.1.XXX"; # replace with actual static IP
  #   prefixLength = 24;
  # }];
  # networking.defaultGateway = "192.168.1.1"; # replace with your router IP
  # networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];
  # networking.useDHCP = false;

  # Override _common: password auth required (server is shared)
  services.openssh.settings.PasswordAuthentication = lib.mkForce true;

  # Laptop-as-server: never sleep, never suspend on lid close
  services.logind.lidSwitch = "ignore";
  services.logind.lidSwitchExternalPower = "ignore";
  # systemd.sleep.extraConfig = ''
  #   AllowSuspend=no
  #   AllowHibernation=no
  #   AllowHybridSleep=no
  #   AllowSuspendThenHibernate=no
  # '';

  # Battery charge thresholds (MSI GF63 — thresholds via TLP)
  services.tlp = {
    enable = true;
    settings = {
      START_CHARGE_THRESH_BAT0 = 40;
      STOP_CHARGE_THRESH_BAT0  = 80;
    };
  };

  users.users.galac = {
    isNormalUser = true;
    extraGroups  = [ "wheel" ];
    # Set password after first boot with: passwd galac
  };

  # Match the NixOS version installed — check with `nixos-version` on lovefield
  system.stateVersion = "25.05";
}
