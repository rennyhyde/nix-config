{ config, lib, ... }:
let
  cfg = config.services.caddy-server;
in {
  # Caddy reverse proxy with wildcard TLS via Cloudflare DNS challenge.
  #
  # One-time setup on each machine:
  #   sudo sh -c 'echo YOUR_CF_TOKEN > /etc/cloudflare/api-token && chmod 600 /etc/cloudflare/api-token'
  # (Same token already used for DDNS — Zone:DNS:Edit + Zone:Read)
  #
  # Usage in a machine's configuration.nix:
  #   services.caddy-server = {
  #     enable     = true;
  #     domain     = "audioboss.win";
  #     email      = "you@example.com";
  #     vpnSubnet  = "10.134.0.0/24";   # required if any expose entry has vpnOnly = true
  #     expose = [
  #       { subdomain = "sync";  port = 8384; vpnOnly = true; }
  #       { subdomain = "music"; port = 4533; }
  #     ];
  #   };

  options.services.caddy-server = {
    enable = lib.mkEnableOption "Caddy reverse proxy with wildcard TLS via Cloudflare";

    domain = lib.mkOption {
      type    = lib.types.str;
      example = "example.com";
      description = "Base domain for this server. Services get <subdomain>.<domain>.";
    };

    email = lib.mkOption {
      type        = lib.types.str;
      description = "Email for ACME/Let's Encrypt registration.";
    };

    cloudflareTokenFile = lib.mkOption {
      type    = lib.types.str;
      default = "/etc/cloudflare/api-token";
      description = "Path to file containing the bare Cloudflare API token.";
    };

    vpnSubnet = lib.mkOption {
      type        = lib.types.nullOr lib.types.str;
      default     = null;
      example     = "10.134.0.0/24";
      description = "CIDR subnet for vpnOnly services. Must match the WireGuard vpnSubnet on this machine.";
    };

    expose = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          subdomain = lib.mkOption { type = lib.types.str; };
          port      = lib.mkOption { type = lib.types.port; };
          vpnOnly   = lib.mkOption {
            type    = lib.types.bool;
            default = false;
            description = "Restrict to vpnSubnet; all other requests get 403.";
          };
        };
      });
      default     = [];
      description = "Services to proxy. Each entry creates <subdomain>.<domain> → localhost:<port>.";
      example     = [ { subdomain = "sync"; port = 8384; vpnOnly = true; } ];
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = !(builtins.any (svc: svc.vpnOnly) cfg.expose) || cfg.vpnSubnet != null;
      message   = "services.caddy-server.vpnSubnet must be set when any expose entry has vpnOnly = true";
    }];

    # Build the ACME environment file from the bare token file.
    # CF_DNS_API_TOKEN_FILE tells lego to read the token from a file,
    # so we can reuse the same secret created for DDNS.
    system.activationScripts.cloudflare-acme-env = ''
      if [ -f "${cfg.cloudflareTokenFile}" ]; then
        mkdir -p /etc/cloudflare
        printf 'CF_DNS_API_TOKEN_FILE=%s\n' "${cfg.cloudflareTokenFile}" > /etc/cloudflare/acme-env
        chmod 600 /etc/cloudflare/acme-env
      else
        echo "caddy: WARNING: Cloudflare token not found at ${cfg.cloudflareTokenFile}" >&2
        echo "  sudo sh -c 'echo YOUR_TOKEN > ${cfg.cloudflareTokenFile} && chmod 600 ${cfg.cloudflareTokenFile}'" >&2
      fi
    '';

    # Wildcard cert — covers *.domain and domain itself.
    # Uses DNS challenge so no port 80/443 exposure needed for renewal.
    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.email;
      certs."${cfg.domain}" = {
        domain            = cfg.domain;
        extraDomainNames  = [ "*.${cfg.domain}" ];
        dnsProvider       = "cloudflare";
        environmentFile   = "/etc/cloudflare/acme-env";
        group             = config.services.caddy.group;
        reloadServices    = [ "caddy.service" ];
      };
    };

    services.caddy = {
      enable = true;
      # Disable Caddy's built-in cert management; security.acme handles it.
      globalConfig = "auto_https off";

      virtualHosts =
        # HTTP → HTTPS redirects for apex and all subdomains
        {
          "http://${cfg.domain}".extraConfig   = "redir https://{host}{uri} permanent";
          "http://*.${cfg.domain}".extraConfig = "redir https://{host}{uri} permanent";
        }
        # One HTTPS virtual host per exposed service
        // lib.listToAttrs (map (svc:
          let
            # Rewrite Host to the upstream address so services that validate
            # the Host header (e.g. Syncthing CSRF check) accept the request.
            proxy = ''
              reverse_proxy localhost:${toString svc.port} {
                header_up Host "127.0.0.1:${toString svc.port}"
              }
            '';
          in {
            name  = "${svc.subdomain}.${cfg.domain}";
            value = {
              useACMEHost = cfg.domain;
              extraConfig = if svc.vpnOnly then ''
                @vpn remote_ip ${cfg.vpnSubnet}
                handle @vpn {
                  ${proxy}
                }
                respond "VPN required" 403
              '' else proxy;
            };
          }
        ) cfg.expose);
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
