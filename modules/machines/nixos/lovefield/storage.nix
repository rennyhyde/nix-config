{ config, lib, pkgs, ... }:
{
  # RAIDZ1 pool "storage" across the 4x2TB USB DAS drives (~5.4TB usable,
  # survives 1 drive failure). Pool itself is created manually on lovefield
  # (needs real /dev/disk/by-id paths for the physical drives) — see
  # ~/Documents/code/lovefield/CLAUDE.md for the runbook. Root stays on ext4.
  boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "b011e6d7";

  boot.zfs.extraPools = [ "storage" ];

  services.zfs.autoScrub.enable = true;
}
