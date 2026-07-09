

# Introduction

# Hardware
**Compute:** Lovefield runs on an MSI GF63 gaming laptop. It is always plugged in
**Storage:** TBD
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
## Wireguard
Wireguard is the VPN protocol that allows users to access lovefield, the local network, and local-only services.

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




## DNS
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

#### Router Port Forward
1. Login to your router's admin page
2. Forward port 51820 to lovefield:
```
Protocol: UDP
External port: 51820
Internal IP: lovefield's static LAN IP
Internal port: 51820
```
