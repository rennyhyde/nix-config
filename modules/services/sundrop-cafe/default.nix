{ config, pkgs, lib, ... }:
let
  cfg = config.services.sundrop-cafe;

  # Static site lives at ./site — index.html, style.css, ripple.js, app.js.
  # Edit those files directly and rebuild; there's no build step.
  siteDir = ./site;

  rsvpScript = ./rsvp_server.py;
in {
  options.services.sundrop-cafe = {
    enable = lib.mkEnableOption "Sundrop Cafe event site (static site + RSVP CSV backend)";

    rsvpPort = lib.mkOption {
      type        = lib.types.port;
      default      = 8098;
      description = "Loopback port the RSVP backend listens on.";
    };
  };

  # Adds sundrop.<domain> to Caddy directly (like hello-world) — only
  # meaningful when caddy-server is also enabled. The whole domain is a
  # static file_server, with just /api/rsvp routed to the local RSVP backend.
  config = lib.mkIf cfg.enable {
    services.caddy.virtualHosts = lib.mkIf config.services.caddy-server.enable {
      "sundrop.${config.services.caddy-server.domain}" = {
        useACMEHost = config.services.caddy-server.domain;
        extraConfig = ''
          root * ${siteDir}
          handle /api/rsvp {
            reverse_proxy localhost:${toString cfg.rsvpPort}
          }
          file_server
        '';
      };
    };

    systemd.services.sundrop-rsvp = {
      description = "Sundrop Cafe RSVP CSV backend";
      wantedBy    = [ "multi-user.target" ];
      after       = [ "network.target" ];
      environment = {
        RSVP_PORT     = toString cfg.rsvpPort;
        RSVP_CSV_PATH = "/var/lib/sundrop-cafe/rsvps.csv";
      };
      serviceConfig = {
        Type            = "simple";
        ExecStart       = "${pkgs.python3}/bin/python3 ${rsvpScript}";
        Restart         = "always";
        RestartSec      = "5s";
        DynamicUser     = true;
        StateDirectory  = "sundrop-cafe";
        # Loopback only — Caddy is the only client, no need for wider network access.
        PrivateNetwork  = false;
      };
    };
  };
}
