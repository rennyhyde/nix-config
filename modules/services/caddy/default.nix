{ config, lib, ... }:
let
  cfg = config.services.caddy-server;

  # Every zone Caddy serves: the primary `domain` plus `extraDomains`, each
  # with its own Cloudflare token (zones can live in different CF accounts).
  tokenFiles = { ${cfg.domain} = cfg.cloudflareTokenFile; }
    // lib.mapAttrs (_: d: d.cloudflareTokenFile) cfg.extraDomains;
  # Primary keeps its original path so existing machines don't churn.
  acmeEnvFile = domain:
    if domain == cfg.domain then "/etc/cloudflare/acme-env"
    else "/etc/cloudflare/acme-env-${domain}";

  svcDomain = svc: if svc.domain == null then cfg.domain else svc.domain;
  svcHost   = svc:
    if svc.subdomain == null then svcDomain svc
    else "${svc.subdomain}.${svcDomain svc}";
in {
  # Caddy reverse proxy with wildcard TLS via Cloudflare DNS challenge.
  #
  # One-time setup on each machine, before rebuilding:
  #   sudo sh -c 'echo YOUR_CF_TOKEN > /etc/cloudflare/api-token'
  # (Same token already used for DDNS — Zone:DNS:Edit + Zone:Read.)
  # Activation then makes each token file acme-owned, mode 0600: lego runs as
  # the acme user and fails with "permission denied" on a root-only token.
  #
  # Usage in a machine's configuration.nix:
  #   services.caddy-server = {
  #     enable     = true;
  #     domain     = "audioboss.win";
  #     email      = "you@example.com";
  #     vpnSubnet  = "10.134.0.0/24";   # required if any expose entry has internalOnly = true
  #     lanSubnet  = "10.0.0.0/24";     # required if any expose entry has internalOnly = true
  #     expose = [
  #       { subdomain = "sync";  port = 8384; internalOnly = true; }
  #       { subdomain = "music"; port = 4533; }
  #       { subdomain = "beta";  port = 3100; basicAuth = { user = "preview"; hash = "$2a$14$..."; }; }
  #       # A zone from extraDomains; subdomain = null serves the apex.
  #       { domain = "example.net"; subdomain = null; port = 3200; }
  #     ];
  #     # Extra zones get their own wildcard cert, issued with their own token.
  #     extraDomains."example.net".cloudflareTokenFile = "/etc/cloudflare/example-net-api-token";
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

    extraDomains = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.cloudflareTokenFile = lib.mkOption {
          type        = lib.types.str;
          description = "Path to file containing the bare Cloudflare API token for this zone.";
        };
      });
      default     = {};
      example     = { "example.net".cloudflareTokenFile = "/etc/cloudflare/example-net-api-token"; };
      description = ''
        Additional zones, each with its own wildcard cert (apex + *.zone). Use
        a separate token per zone when the zones are in different Cloudflare
        accounts. Expose entries pick a zone with their `domain` option.
      '';
    };

    vpnSubnet = lib.mkOption {
      type        = lib.types.nullOr lib.types.str;
      default     = null;
      example     = "10.134.0.0/24";
      description = "CIDR subnet for internalOnly services. Must match the WireGuard vpnSubnet on this machine.";
    };

    lanSubnet = lib.mkOption {
      type        = lib.types.nullOr lib.types.str;
      default     = null;
      example     = "10.0.0.0/24";
      description = "CIDR subnet for internalOnly services. Must match this machine's LAN.";
    };

    expose = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          subdomain    = lib.mkOption {
            type        = lib.types.nullOr lib.types.str;
            description = "Subdomain to serve on; null serves the zone apex.";
          };
          domain       = lib.mkOption {
            type        = lib.types.nullOr lib.types.str;
            default     = null;
            description = "Zone to serve on: null for `domain`, otherwise a key of `extraDomains`.";
          };
          port         = lib.mkOption { type = lib.types.port; };
          internalOnly = lib.mkOption {
            type    = lib.types.bool;
            default = false;
            description = "Restrict to vpnSubnet/lanSubnet; all other requests get 403.";
          };
          rewriteHost = lib.mkOption {
            type        = lib.types.bool;
            default     = true;
            description = ''
              Rewrite the upstream Host header to 127.0.0.1:<port> (needed by
              services with a Host/CSRF check, e.g. Syncthing). Set false for
              services that must see the public hostname (cookies, generated URLs).
            '';
          };
          basicAuth = lib.mkOption {
            type = lib.types.nullOr (lib.types.submodule {
              options = {
                user = lib.mkOption { type = lib.types.str; };
                hash = lib.mkOption {
                  type        = lib.types.str;
                  description = "bcrypt hash, from `nix run nixpkgs#caddy -- hash-password`.";
                };
              };
            });
            default     = null;
            description = "Require HTTP basic auth from clients outside vpnSubnet/lanSubnet; internal clients get in without it.";
          };
        };
      });
      default     = [];
      description = "Services to proxy. Each entry creates <subdomain>.<domain> (or <domain> itself) → localhost:<port>.";
      example     = [ { subdomain = "sync"; port = 8384; internalOnly = true; } ];
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = !(builtins.any (svc: svc.internalOnly) cfg.expose)
                  || cfg.vpnSubnet != null || cfg.lanSubnet != null;
      message   = "services.caddy-server.vpnSubnet or lanSubnet must be set when any expose entry has internalOnly = true";
    }] ++ map (svc: {
      # Two hosts on one port means one of them silently proxies to the wrong
      # service, possibly a public host onto an internal-only one.
      assertion = builtins.length (builtins.filter (o: o.port == svc.port) cfg.expose) == 1;
      message   = "services.caddy-server.expose.${svcHost svc}: port ${toString svc.port} is used by more than one expose entry";
    }) cfg.expose
    ++ map (svc: {
      assertion = svc.domain == null || svc.domain == cfg.domain || cfg.extraDomains ? ${svc.domain};
      message   = "services.caddy-server.expose.${svcHost svc}: domain must be services.caddy-server.domain or a key of extraDomains";
    }) cfg.expose
    ++ lib.concatMap (svc: lib.optionals (svc.basicAuth != null) [
      {
        assertion = !svc.internalOnly;
        message   = "services.caddy-server.expose.${svcHost svc}: internalOnly and basicAuth are mutually exclusive";
      }
      {
        assertion = cfg.vpnSubnet != null || cfg.lanSubnet != null;
        message   = "services.caddy-server.vpnSubnet or lanSubnet must be set when any expose entry has basicAuth";
      }
      {
        # A malformed hash fails Caddy's config load, taking every vhost down
        # with it — catch it (and an unreplaced placeholder) at build time.
        assertion = lib.hasPrefix "$2" svc.basicAuth.hash;
        message   = "services.caddy-server.expose.${svcHost svc}: basicAuth.hash must be a bcrypt hash (generate with `nix run nixpkgs#caddy -- hash-password`)";
      }
    ]) cfg.expose;

    # Build the ACME environment file for each zone from its bare token file.
    # CF_DNS_API_TOKEN_FILE tells lego to read the token from a file,
    # so we can reuse the same secret created for DDNS.
    # lego opens that file itself as the acme user, so the token must be
    # readable by acme. Making acme the owner (rather than relying on group
    # access) works regardless of the unit's Group=, which is the cert's group
    # (caddy). DDNS is unaffected: it reads the token as root via LoadCredential.
    # deps: the acme user must exist before the chown (fresh installs).
    system.activationScripts.cloudflare-acme-env.deps = [ "users" ];
    system.activationScripts.cloudflare-acme-env.text = lib.concatStrings (lib.mapAttrsToList (domain: tokenFile: ''
      if [ -f "${tokenFile}" ]; then
        mkdir -p /etc/cloudflare
        printf 'CF_DNS_API_TOKEN_FILE=%s\n' "${tokenFile}" > ${acmeEnvFile domain}
        chmod 600 ${acmeEnvFile domain}
        chown acme:acme "${tokenFile}"
        chmod 600 "${tokenFile}"
      else
        echo "caddy: WARNING: Cloudflare token for ${domain} not found at ${tokenFile}" >&2
        echo "  sudo sh -c 'echo YOUR_TOKEN > ${tokenFile}' && rebuild" >&2
      fi
    '') tokenFiles);

    # Wildcard cert per zone — covers *.domain and domain itself.
    # Uses DNS challenge so no port 80/443 exposure needed for renewal.
    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.email;
      certs = lib.mapAttrs (domain: _: {
        domain            = domain;
        extraDomainNames  = [ "*.${domain}" ];
        dnsProvider       = "cloudflare";
        environmentFile   = acmeEnvFile domain;
        group             = config.services.caddy.group;
        reloadServices    = [ "caddy.service" ];
        # Local resolver doesn't return SOA for external zones; force lego to use 8.8.8.8.
        extraLegoFlags    = [ "--dns.resolvers" "8.8.8.8:53" ];
      }) tokenFiles;
    };

    services.caddy = {
      enable = true;
      # Disable Caddy's built-in cert management; security.acme handles it.
      globalConfig = "auto_https off";

      virtualHosts =
        # HTTP → HTTPS redirects for apex and all subdomains of every zone
        lib.concatMapAttrs (domain: _: {
          "http://${domain}".extraConfig   = "redir https://{host}{uri} permanent";
          "http://*.${domain}".extraConfig = "redir https://{host}{uri} permanent";
        }) tokenFiles
        # One HTTPS virtual host per exposed service
        // lib.listToAttrs (map (svc:
          let
            # Rewrite Host to the upstream address so services that validate
            # the Host header (e.g. Syncthing CSRF check) accept the request.
            proxy = if svc.rewriteHost then ''
              reverse_proxy localhost:${toString svc.port} {
                header_up Host "127.0.0.1:${toString svc.port}"
              }
            '' else ''
              reverse_proxy localhost:${toString svc.port}
            '';
            internalSubnets = builtins.filter (s: s != null) [ cfg.vpnSubnet cfg.lanSubnet ];
          in {
            name  = svcHost svc;
            value = {
              useACMEHost = svcDomain svc;
              # Caddyfile directives are NOT executed in the order they're written — Caddy
              # sorts them into its own fixed global order first. A bare `handle` next to a
              # bare `respond` at the top level is exactly the case where that reordering can
              # put `respond` ahead of `handle`, causing the 403 to fire unconditionally even
              # for matched (internal) requests. Wrapping in `route {}` forces the directives
              # inside to run in the written order, and pairing `handle`/`handle` (rather than
              # `handle`/bare `respond`) is Caddy's documented mutual-exclusion idiom.
              extraConfig = if svc.internalOnly then ''
                route {
                  @internal remote_ip ${lib.concatStringsSep " " internalSubnets}
                  handle @internal {
                    ${proxy}
                  }
                  handle {
                    respond "Internal network required" 403
                  }
                }
              '' else if svc.basicAuth != null then ''
                route {
                  @internal remote_ip ${lib.concatStringsSep " " internalSubnets}
                  handle @internal {
                    ${proxy}
                  }
                  handle {
                    basic_auth {
                      ${svc.basicAuth.user} ${svc.basicAuth.hash}
                    }
                    ${proxy}
                  }
                }
              '' else proxy;
            };
          }
        ) cfg.expose);
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
