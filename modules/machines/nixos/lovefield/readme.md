

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

**Important:** `mutableSettings = false` — AdGuard's config (`/var/lib/AdGuardHome/AdGuardHome.yaml`) is fully Nix-managed and gets overwritten on every `nixos-rebuild switch`. Any changes made through the AdGuard web UI (new rewrites, filter rules, DHCP settings, etc.) will be **silently reverted** on the next rebuild unless they're also added to `services.adguardhome.settings` in `configuration.nix`. Make changes in the Nix config, not the UI, if they need to persist.

## Immich
Self-hosted photo backup, running as podman containers via `virtualisation.oci-containers` (upstream's official images — nixpkgs' `immich` package trails releases, so it isn't used). Reachable at `https://photos.audioboss.win` from the LAN or VPN (resolved locally by AdGuard's `*.audioboss.win` rewrite); not in the `cloudflare-dyndns` domain list, so it has no public DNS record and isn't reachable from the WAN.

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

### Machine Learning (intentionally not deployed)
The `immich-machine-learning` container (smart search, face recognition, OCR) is not deployed — CPU-only inference isn't worth the thermal load on this hardware (see the fan-control hack above). `podman-immich-server` logs will show repeated `Machine learning request ... failed for all URLs` / `Machine learning server became unhealthy (http://immich-machine-learning:3003)` warnings — this is expected and harmless, Immich just falls back to not having those features. Can be added later (matching container shape as the other three) with zero data migration if the hardware situation changes.

## Proton VPN + qBittorrent
qBittorrent runs confined to an isolated network namespace (`protonvpn`) whose only route out is a Proton VPN WireGuard tunnel — this is a real kill switch, not just "usually tunneled": the namespace has no other interface or route, so if the tunnel drops, qBittorrent's traffic simply stops rather than falling back to the home WAN. Two modules implement this:
- `modules/services/wireguard-netns` — generic: creates the namespace and brings up a raw WireGuard interface inside it (interface name `pvpn0`, not `wg0` — that name is already taken in the root namespace by the WireGuard *server*, see Known Issues below).
- `modules/services/qbittorrent-vpn` — runs `qbittorrent-nox` joined to that namespace (`NetworkNamespacePath`), and bridges its WebUI back out to the host loopback via a `systemd-socket-proxyd` unit (mirrors the deluge pattern in Wolfgang's reference config) so Caddy — which lives in the normal namespace — can still reverse-proxy to it at `https://torrent.audioboss.win` (VPN/LAN-only).

Only qBittorrent's traffic goes through Proton this way. Everything else (Jellyfin, Navidrome, Samba, Immich, Forgejo, AdGuard, the WireGuard server's own control traffic) is untouched and keeps using the normal default route. Routing *remote WireGuard clients'* general web traffic through Proton too (so it's hidden from lovefield's home ISP, not just qBittorrent's torrent traffic) is a separate, not-yet-implemented piece — see Open Questions in `CLAUDE.md`.

### First Time Setup
1. Proton dashboard → Downloads → WireGuard configuration → pick a **P2P** server (P2P icon), enable **NAT-PMP (port forwarding)** if the plan tier supports it (Plus/Unlimited — improves torrent connectivity, not required for correctness).
2. The downloaded file is a `wg-quick` config; this module wants only the raw peer info, **without** the `Address`/`DNS` lines under `[Interface]`:
   ```
   sudo mkdir -p /etc/proton-vpn
   sudo tee /etc/proton-vpn/qbittorrent.conf <<'EOF'
   [Interface]
   PrivateKey = <from Proton's file>

   [Peer]
   PublicKey = <from Proton's file>
   Endpoint = <from Proton's file>
   AllowedIPs = 0.0.0.0/0
   EOF
   sudo chmod 600 /etc/proton-vpn/qbittorrent.conf
   ```
3. Set `services.wireguard-netns.address` in `configuration.nix` to the `Address = 10.x.x.x/32` line from Proton's original downloaded file, then rebuild.
4. First WebUI login: grab the auto-generated temporary password with `journalctl -u qbittorrent-nox | grep -i "temporary password"`, then change the username/password immediately under Options → Web UI — nothing in Nix manages `qBittorrent.conf`, so anything set there persists across rebuilds.
5. Options → Downloads → **Default Save Path** → `/mnt/storage/media/downloads/torrent`. No CLI flag sets this (qBittorrent's `--save-path` only applies to torrents passed positionally on the command line at startup), so it has to be set once here.

### Verifying the tunnel and kill switch (do this before torrenting anything)
```zsh
sudo ip netns exec protonvpn curl -s ifconfig.me                     # should be a Proton exit IP, never lovefield's home IP
sudo ip netns exec protonvpn ip link set pvpn0 down                  # simulate a dropped tunnel
sudo ip netns exec protonvpn curl -s --max-time 5 ifconfig.me        # must hang/fail — no fallback to the real WAN
sudo ip netns exec protonvpn ip link set pvpn0 up
sudo systemctl restart protonvpn                                     # re-establish cleanly
```
In the qBittorrent WebUI, cross-check a torrent's reported peer-facing IP against the Proton exit IP from the first command above.

### Sorting downloads into Jellyfin's library while still seeding
`/mnt/storage/media/{downloads,movies,tv,...}` are all in the same `storage/media` ZFS dataset (see Storage section above), so moving a finished download into the library is an instant rename, not a copy — qBittorrent keeps seeding from the new location with no interruption.
1. Options → Downloads → confirm Torrent Management Mode is **Automatic**.
2. Categories panel → add a category per library folder, e.g. `movies` → `/mnt/storage/media/movies`, `tv` → `/mnt/storage/media/tv`.
3. Assign a torrent's category (at add-time, or later via right-click → Category on an existing torrent) and qBittorrent relocates the files there automatically, then keeps seeding from the new path.
4. Any new subfolder added under `/mnt/storage/media/` for this (or anything else) needs the same ownership as its siblings or qBittorrent/Jellyfin will get permission-denied writing/reading it — see Known Issues.

### Common Commands
```zsh
sudo systemctl status protonvpn qbittorrent-nox qbittorrent-webui-proxy
sudo ip netns exec protonvpn wg show                  # tunnel handshake/traffic stats
sudo ip netns list
```

# Known Issues

## `*.audioboss.win` breaks in Firefox/Chrome but works in Safari
**Symptom:** A local service (e.g. `photos.audioboss.win`) loads fine in Safari, but Chrome says the address is unreachable and Firefox returns a `500 Internal Server Error` — even on the LAN with no VPN.

**Cause:** Firefox ships with DNS-over-HTTPS (DoH) enabled by default, pointed at a public resolver (Cloudflare). Chrome's "Secure DNS" can behave similarly. Both bypass the network's actual DNS server entirely, so they never see AdGuard Home's `*.audioboss.win → 10.0.0.5` rewrite — instead they get whatever (if anything) the public `audioboss.win` Cloudflare zone has for that name, which is unrelated to lovefield and can respond in confusing, browser-specific ways. Safari respects the system/network DNS resolver and isn't affected.

**Fix:**
- **Firefox** auto-disables DoH on a network if a specific canary domain (`use-application-dns.net`) fails to resolve. AdGuard is configured (`services.adguardhome.settings.user_rules` in `configuration.nix`) to block that domain, which fixes this automatically for every device on the LAN/VPN — no per-device Firefox config needed.
- **Chrome** doesn't honor that canary and needs a manual per-device toggle: `chrome://settings/security` → **Use secure DNS** → set to "With your current service provider" (or off).

**Diagnosing DNS issues like this in general:** compare `dig <name>` (whatever the system resolver returns) against `dig <name> @10.0.0.5` (AdGuard directly). If they differ, something on the client is bypassing the network's DNS server (DoH, a VPN profile's DNS override, manually-set DNS servers, etc.) rather than lovefield being misconfigured.

## AdGuard Home and podman container networking fight over port 53
If AdGuard's `dns.bind_hosts` is set to `0.0.0.0` (bind all interfaces), it claims port 53 on *every* interface — including the gateway IP of any podman bridge network (e.g. `10.89.0.1`). This silently breaks `aardvark-dns`, podman's container-name DNS resolution (what lets `immich-server` find `immich-postgres` by name), with errors like `failed to bind udp listener on 10.89.0.1:53: Address already in use`.

Fixed by binding AdGuard to specific addresses instead of `0.0.0.0` (`services.adguardhome.settings.dns.bind_hosts` in `configuration.nix`). Worth remembering if a *future* podman/oci-container service mysteriously can't resolve its sibling containers by name — check `sudo journalctl -u podman-<name> | grep aardvark` for this exact symptom before assuming the container config is wrong.

## `wireguard-netns` interface name collides with the WireGuard server's `wg0`
**Symptom:** `protonvpn.service` (from `modules/services/wireguard-netns`) fails immediately with `RTNETLINK answers: File exists`.

**Cause:** The bring-up script creates its WireGuard link in the *root* namespace first, then moves it into the target namespace (`ip link set <if> netns protonvpn`) — that's just how `ip link` works, an interface can't be created directly inside another namespace. If it's named `wg0`, that collides with the WireGuard remote-access server's own `wg0` interface, which already lives in the root namespace.

**Fix:** `services.wireguard-netns.interfaceName` (default `pvpn0`) exists specifically to avoid this — any *other* future netns-confined service should pick its own distinct name too, not reuse `wg0` or `pvpn0`.

## New subfolders under `/mnt/storage/media/` need explicit ownership
**Symptom:** A service (qBittorrent, Jellyfin, Samba, ...) gets a permission-denied error writing to or reading a newly created folder under `/mnt/storage/media/`, even though sibling folders like `movies`/`tv`/`downloads` work fine.

**Cause:** `chown -R root:media` + `chmod -R 2775` was applied once, at pool-creation time (see Storage section above). The setgid bit (`2`) makes *files and folders created inside an already-correct folder* inherit the `media` group, but a brand new top-level folder created directly under `/mnt/storage/media/` (e.g. `mkdir /mnt/storage/media/software`) doesn't retroactively get that treatment unless it was created *inside* a setgid folder — a bare `mkdir` at that level can land as `root:root` or whatever the creating user's default group is.

**Fix:** whenever adding a new folder directly under `/mnt/storage/media/`:
```zsh
sudo chown root:media /mnt/storage/media/<new-folder>
sudo chmod 2775 /mnt/storage/media/<new-folder>
```
