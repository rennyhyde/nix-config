{ config, lib, ... }:
let
  cfg = config.services.cloudflare-dyndns;
in {
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
  #
  # Zones in a *different* Cloudflare account need their own token, so they get
  # their own instance via services.cloudflare-dyndns-zones (below), e.g.:
  #   services.cloudflare-dyndns-zones.pocketnoise = {
  #     apiTokenFile = "/etc/cloudflare/pocketnoise-api-token";
  #     domains      = [ "pocketnoise.net" ];
  #   };
  # Each runs as its own unit, cloudflare-dyndns-<name>, sharing the package,
  # frequency, and ipv4/ipv6/proxied settings of the main instance.

  options.services.cloudflare-dyndns-zones = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        apiTokenFile = lib.mkOption {
          type        = lib.types.str;
          description = "Path to file containing the bare Cloudflare API token for these domains.";
        };
        domains = lib.mkOption {
          type        = lib.types.listOf lib.types.str;
          description = "Domain names to update records for.";
        };
      };
    });
    default     = {};
    description = "Extra cloudflare-dyndns instances, one per Cloudflare API token.";
  };

  config = {
    services.cloudflare-dyndns = {
      enable = true;
      apiTokenFile = "/etc/cloudflare/api-token";
      proxied = false;
      ipv4 = true;
      ipv6 = false;
      # domains = [
      #   "audioboss.win"        # apex — update to your actual domain
      #   "vpn.audioboss.win"    # WireGuard endpoint
      # ];
    };

    # Clone of the upstream unit (nixpkgs services/networking/cloudflare-dyndns.nix)
    # with its own token, domains, and state dir — the IP cache is per-instance,
    # otherwise one instance's cache hit would skip the other's update.
    systemd.services = lib.mapAttrs' (name: zone: lib.nameValuePair "cloudflare-dyndns-${name}" ({
      description = "CloudFlare Dynamic DNS Client (${name})";
      after       = [ "network.target" ];
      wantedBy    = [ "multi-user.target" ];

      environment.CLOUDFLARE_DOMAINS = toString zone.domains;

      serviceConfig = {
        Type           = "simple";
        DynamicUser    = true;
        StateDirectory = "cloudflare-dyndns-${name}";
        Environment    = [ "XDG_CACHE_HOME=%S/cloudflare-dyndns-${name}/.cache" ];
        LoadCredential = [ "apiToken:${zone.apiTokenFile}" ];
      };

      script =
        let
          args = [ "--cache-file /var/lib/cloudflare-dyndns-${name}/ip.cache" ]
            ++ (if cfg.ipv4 then [ "-4" ] else [ "-no-4" ])
            ++ (if cfg.ipv6 then [ "-6" ] else [ "-no-6" ])
            ++ lib.optional cfg.deleteMissing "--delete-missing"
            ++ lib.optional cfg.proxied "--proxied";
        in ''
          export CLOUDFLARE_API_TOKEN_FILE=''${CREDENTIALS_DIRECTORY}/apiToken
          exec ${lib.getExe cfg.package} ${toString args}
        '';
    } // lib.optionalAttrs (cfg.frequency != null) {
      startAt = cfg.frequency;
    })) config.services.cloudflare-dyndns-zones;
  };
}
