

# Introduction

# Hardware
**Compute:** Lovefield runs on an MSI GF63 gaming laptop. It is always plugged in
**Storage:** 1TB internal SSD (root, ext4) + 4x2TB USB DAS drives in a ZFS RAIDZ1 pool named `storage` (~5.4TB usable, survives 1 drive failure), mounted per-service under `/mnt/storage/`. An older 1TB USB HDD is also attached but currently unmounted/unused.
**Network:** Connected directly to router via ethernet

# Owner's Guide
## Moving Lovefield
Lovefield will automatically boot up with no interaction from the user. However, if the static IP set on the router has changed, lovefield will fail to connect to the network. It doesn't matter what static IP, just as long as the IP is static. If you get a new router or reset your router, make sure to reserve a static IP for lovefield's MAC address.
Also, make sure to connect any storage drives to lovefield before booting up to ensure that the server does not freak out about missing data.

## Power Outage
Hopefully lovefield's built-in battery will allow it to shut down gracefully in the event of a power outage. TODO: Verify.

## Physical Maintenance
Every once and a while, check to make sure the heat levels on the keyboard and around the laptop are reasonable. If they aren't, it may indicate a fan failure, which is pretty serious.
Remove dust occasionally.

# Installation Runbook


# Configuration Notes
- Mir's wifi router:
	- User: `admin`
	- PW: `Stonehenge!`
- NixOS setup
	- User: `galac`
	- PW: `kn0ck0nw000d`
	- Swap, no hibernate
- Static IP config
	- `enp3s0` -> lovefield ethernet interface
	- `10.0.0.5` -> lovefield IP
	- Set on router side, not in nix config
		- TODO: Test setting it in nix config eventually
- Dynamic DNS (DDNS)
	- Needed so that wireguard knows what endpoint to send encrypted traffic to, since ISP changes public IP leasing from time to time
    - `audioboss.win` DNS records hosted on cloudflare, updated via ddclient and a Cloudflare API token

# Services
## Storage (ZFS RAIDZ1)
The `storage` pool spans the 4 drives on the USB DAS in a RAIDZ1 vdev (~5.4TB usable, tolerates 1 drive failure). Datasets are mounted per-service under `/mnt/storage/`. `boot.zfs.extraPools` and `networking.hostId` in `storage.nix` handle auto-import/mount at boot; the pool and datasets themselves are created manually since they need real `/dev/disk/by-id` paths.

### Bay → drive mapping
The USB DAS uses a JMicron bridge that doesn't pass through each drive's real serial over USB — its `by-id` name only identifies a **bay** (via the trailing SCSI target `-0:N`), not a specific physical disk. If a drive is ever pulled for replacement, use this table to know which physical WD drive was in which bay:

| bay/dev | by-id | WD serial |
|---|---|---|
| sda | `usb-JMicron_Generic_DISK00_0123456789ABCDEF-0:0` | WD-WCC4M0626885 |
| sdb | `usb-JMicron_Generic_DISK01_0123456789ABCDEF-0:1` | WD-WCC4M0594521 |
| sdc | `usb-JMicron_Generic_DISK02_0123456789ABCDEF-0:2` | WD-WCC4M0579554 |
| sdd | `usb-JMicron_Generic_DISK03_0123456789ABCDEF-0:3` | WD-WCC4M0594460 |

### Creating the pool (one-time)
1. Identify the 4 new drives: `lsblk -o NAME,SIZE,MODEL,SERIAL` and `ls -la /dev/disk/by-id/ | grep -i usb`. Confirm exactly 4 devices at ~1.8TiB, distinct from the internal SSD and the old 1TB HDD. (Already done above — see the bay/serial table.)
2. Wipe them (destructive — double check the disk IDs first):
   ```
   sudo wipefs -a /dev/disk/by-id/usb-JMicron_Generic_DISK00_0123456789ABCDEF-0:0
   sudo wipefs -a /dev/disk/by-id/usb-JMicron_Generic_DISK01_0123456789ABCDEF-0:1
   sudo wipefs -a /dev/disk/by-id/usb-JMicron_Generic_DISK02_0123456789ABCDEF-0:2
   sudo wipefs -a /dev/disk/by-id/usb-JMicron_Generic_DISK03_0123456789ABCDEF-0:3
   ```
3. Create the pool:
   ```
   sudo zpool create -o ashift=12 -O mountpoint=none storage raidz1 \
     /dev/disk/by-id/usb-JMicron_Generic_DISK00_0123456789ABCDEF-0:0 \
     /dev/disk/by-id/usb-JMicron_Generic_DISK01_0123456789ABCDEF-0:1 \
     /dev/disk/by-id/usb-JMicron_Generic_DISK02_0123456789ABCDEF-0:2 \
     /dev/disk/by-id/usb-JMicron_Generic_DISK03_0123456789ABCDEF-0:3
   ```
4. Create per-service datasets:
   ```
   sudo zfs create -o mountpoint=/mnt/storage/syncthing/galac storage/syncthing-galac
   sudo zfs create -o mountpoint=/mnt/storage/syncthing/mir   storage/syncthing-mir
   sudo zfs create -o mountpoint=/mnt/storage/immich          storage/immich
   sudo zfs create -o mountpoint=/mnt/storage/media           storage/media
   sudo zfs create -o mountpoint=/mnt/storage/paperless       storage/paperless
   sudo zfs create -o mountpoint=/mnt/storage/navidrome       storage/navidrome
   sudo chown galac:users /mnt/storage/syncthing/galac
   sudo chown mir:users   /mnt/storage/syncthing/mir

   sudo mkdir -p /mnt/storage/media/{movies,tv,downloads}
   sudo groupadd media
   sudo usermod -aG media galac
   sudo usermod -aG media mir
   sudo chown -R root:media /mnt/storage/media
   sudo chmod -R 2775 /mnt/storage/media   # setgid so new files/dirs inherit the `media` group
   ```
   `storage/media` is a **shared** dataset, not per-service: Jellyfin, Samba, and any future download automation (Sonarr/Radarr/qBittorrent-style tools) all read/write the same `movies/`, `tv/`, `downloads/` tree. This matters because ZFS datasets are separate filesystems even within one pool — hardlinks (how those download tools do an instant, no-copy move from `downloads/` into the library) don't work *across* datasets, only within one. Keeping them all under `storage/media` is what makes that work. Once Jellyfin's/Samba's NixOS modules exist, add their service users to the `media` group instead of relying on `galac`/`mir` membership.

   Paperless/Navidrome datasets stay root-owned until those services' NixOS modules exist and their real service-user UIDs are known. Immich's subpaths are chowned automatically by `systemd.tmpfiles.rules` — see the Immich section below. Add more datasets any time with `zfs create`.
5. Point each user's Syncthing folders (via its web GUI, not Nix) at `/mnt/storage/syncthing/<user>/...`.

### Common Commands
```zsh
sudo zpool status storage   # pool + drive health
sudo zfs list                # datasets and mountpoints
df -h /mnt/storage/*
```

### Simulating a drive failure (optional, to verify the "1 drive failure" guarantee)
```zsh
sudo zpool offline storage <disk-by-id>   # pool goes DEGRADED, stays online
sudo zpool online storage <disk-by-id>    # resilvers back to healthy
```

## Wireguard
Wireguard is the VPN protocol that allows users to access lovefield, the local network, and local-only services.

### Router Port Forward
1. Login to your router's admin page
2. Forward port 51820 to lovefield:
```
Protocol: UDP
External port: 51820
Internal IP: lovefield's static LAN IP
Internal port: 51820
```

### Provisioning a New Client
1. Add the client name to `lovefield/configuration.nix`. No spaces.
2. Rebuild on Lovefield. Connections (probably) won't be dropped.
3. If joining from a device that can scan QR codes:
`sudo cat etc/wireguard/clients/${CLIENT-NAME}/qr.txt`
Otherwise, copy the configuration file (`etc/wireguard/clients/${CLIENT-NAME}`) and import it into wireguard directly.

### Getting Connected
#### QR Code (WG app on Mobile Phone or Tablet)
1. Run `sudo cat /etc/wireguard/clients/${CLIENT-NAME}/qr.txt`
2. If the QR code looks weird and jumbled, zoom out in your terminal
3. Open the Wireguard app > Plus to add client > Scan from QR code
4. Scan the QR code
5. Activate the VPN tunnel by sliding the switch ON.
6. When you're finished, close the tunnel by sliding the switch OFF.

#### Config File (WG app on any platform)
1. Copy the config from lovefield to your device. On Linux, it would look like:
```zsh
mkdir -p /etc/wireguard/	# Create the wireguard configuration dir. if it doesn't already exist
scp ${USERNAME}@10.0.0.5:/etc/wireguard/clients/${CLIENT-NAME}/client.conf /etc/wireguard/lovefield.conf	# Copy the config over from lovefield
```
2. In the WG app, select "Import from file or archive" and import the config file
3. Activate the VPN tunnel by sliding the switch ON.
4. When you're finished, close the tunnel by sliding the switch OFF.

#### Config File (Command Line)
The WireGuard app for MacOS is gated behind the Mac App Store, which I don't want to sign into. Luckily you can do all this without a gui, in the command line.
1. Make sure `wireguard-tools` are installed. See: https://www.wireguard.com/install/
2. Copy your config file over to your device. On linux it would look like:
```zsh
mkdir -p /etc/wireguard/	# Create the wireguard configuration dir. if it doesn't already exist
scp ${USERNAME}@10.0.0.5:/etc/wireguard/clients/${CLIENT-NAME}/client.conf /etc/wireguard/lovefield.conf	# Copy the config over from lovefield
```
3. Activate tunnel with `wg-quick up lovefield`
4. Close the tunnel with `wg-quick down lovefield`


### Common Commands
```zsh
# Check connected clients (on lovefield)
sudo wg show
```




## Dynamic DNS
DNS records for `audioboss.win` are updated automatically by `ddclient` to point to lovefield. DNS records are hosted on cloudflare, and updated using a cloudflare API key.

### First Time Setup
API key is NOT included in the nix config. Here is the runbook to set up DDNS on a fresh machine:

#### Generate Cloudflare API key
1. Go to `Dashboard > My Profile > API Tokens > Create Token`
2. Select `DNS -> Edit` and `Zone -> Read`
3. Copy and save the token, you will not be able to get it back after this
4. On lovefield, add the API key:
```
sudo mkdir -p /etc/cloudflare
echo "PASTE_YOUR_TOKEN_HERE" | sudo tee /etc/cloudflare/api-token
sudo chmod 600 /etc/cloudflare/api-token
```

## Adguard Home
Adguard Home serves two purposes: It blocks ads and trackers on the local network by being set as the primary DNS server for all LAN requests, and it contains specific DNS rewrites which point audioboss.win services to lovefield instead of back to the router, which triggers the hairpin NAT issue.

### Setup
#### Nix Config
1. Set a password hash using `htpasswd -nbB admin 'your-chosen-password' | cut -d: -f2` for the admin account. Otherwise there will not be an admin account
2. Add DNS rewrites for local services

## Immich
Self-hosted photo backup, running as podman containers via `virtualisation.oci-containers` (upstream's official images — nixpkgs' `immich` package trails releases, so it isn't used). VPN-only: reachable at `https://photos.audioboss.win` only from a WireGuard client; not in the DDNS domain list, so it isn't publicly resolvable at all.

### First Time Setup
The DB password is NOT included in the nix config (this repo is public). Runbook to set it up on a fresh machine:

1. On your Mac, create a local file (not in this repo) containing:
   ```
   DB_PASSWORD=<random password, letters/numbers only>
   POSTGRES_PASSWORD=<same value>
   ```
2. Copy it to lovefield and lock it down. `--chmod=600` requires GNU rsync (macOS's built-in rsync doesn't support the bare-octal form, use `Fu=rw,Fgo=` instead); `-t` on ssh forces a TTY so the sudo password prompt works:
   ```zsh
   rsync -av --chmod=Fu=rw,Fgo= ./immich-db.env galac@10.0.0.5:/tmp/immich-db.env
   ssh -t galac@10.0.0.5 'sudo install -o root -g root -m 600 /tmp/immich-db.env /etc/immich/db.env && rm /tmp/immich-db.env'
   ```
3. Rebuild. `systemctl status podman-immich-postgres podman-immich-redis podman-immich-server` should all show `active (running)`. Without `/etc/immich/db.env` in place, the containers fail to start with a clear "no such file" error.
4. Visit `https://photos.audioboss.win` over the VPN and complete Immich's first-run admin account setup.

### Storage
Uploads live at `/mnt/storage/immich/upload`; Postgres data at `/mnt/storage/immich/postgres` (uid 999, matching the `ghcr.io/immich-app/postgres` image's postgres user). Both directories are created automatically via `systemd.tmpfiles.rules` in `configuration.nix`.

### Upgrading
The `immich-server`/`immich-postgres` image tags are pinned explicitly in `configuration.nix` (not `:release`) for controlled upgrades. Check https://docs.immich.app/install/upgrading before bumping — occasionally a version requires a specific upgrade path or manual step.
