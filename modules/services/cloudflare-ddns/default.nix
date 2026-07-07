{ ... }:
{
  # Cloudflare Dynamic DNS — keeps A records updated when home IP changes.
  #
  # One-time setup on lovefield before rebuilding:
  #   sudo mkdir -p /etc/cloudflare
  #   echo "YOUR_API_TOKEN" | sudo tee /etc/cloudflare/api-token
  #   sudo chmod 600 /etc/cloudflare/api-token
  #
  # Token: Cloudflare Dashboard → My Profile → API Tokens → Create Token
  #   Template: "Edit zone DNS"
  #   Zone Resources: Include → Specific zone → your domain
  #   (This same token is reused by Caddy for ACME wildcard certs later.)
  #
  # proxied = false: required — Cloudflare proxy is HTTP only; WireGuard (UDP) must be DNS-only.
  # Enable proxy per-record in the Cloudflare dashboard later for HTTP services if desired.

  services.cloudflare-dyndns = {
    enable = true;
    apiTokenFile = "/etc/cloudflare/api-token";
    proxied = false;
    ipv4 = true;
    ipv6 = false;
    domains = [
      "audioboss.win"        # apex — update to your actual domain
      "vpn.audioboss.win"    # WireGuard endpoint
    ];
  };
}
