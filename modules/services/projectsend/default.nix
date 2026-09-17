{ config, pkgs, lib, ... }:
let
  cfg = config.services.projectsend;
in {
  # ProjectSend (https://github.com/projectsend/projectsend) — self-hosted
  # large-file sharing: upload a folder, share it with specific email
  # addresses, set a download expiry, attach a message. Runs as three podman
  # containers (app + MySQL + Redis), same pattern as Immich in lovefield's
  # configuration.nix — upstream's official image, not a nixpkgs package.
  #
  # One-time setup on each machine before enabling:
  #   sudo mkdir -p /etc/projectsend
  #   sudo tee /etc/projectsend/secrets.env <<'EOF'
  #   DB_PASSWORD=<random password, letters/numbers only>
  #   MYSQL_PASSWORD=<same value as DB_PASSWORD>
  #   MYSQL_ROOT_PASSWORD=<a different random password>
  #   ADMIN_EMAIL=<first admin account email>
  #   ADMIN_PASSWORD=<first admin account password>
  #   MAIL_USERNAME=<SMTP username, if mail.host is set below>
  #   MAIL_PASSWORD=<SMTP password, if mail.host is set below>
  #   EOF
  #   sudo chmod 600 /etc/projectsend/secrets.env
  #
  # Usage in a machine's configuration.nix:
  #   services.projectsend = {
  #     enable  = true;
  #     appUrl  = "https://share.example.com";
  #     dataDir = "/mnt/storage/projectsend";  # defaults to /var/lib/projectsend
  #     mail = {
  #       host        = "smtp.example.com";
  #       fromAddress = "share@example.com";
  #     };
  #   };
  # Then add { subdomain = "share"; port = config.services.projectsend.port; }
  # to services.caddy-server.expose and "share.example.com" to
  # services.cloudflare-dyndns.domains (this needs to be public — the whole
  # point is that people outside the VPN/LAN receive download links).

  options.services.projectsend = {
    enable = lib.mkEnableOption "ProjectSend self-hosted file-sharing platform";

    appUrl = lib.mkOption {
      type        = lib.types.str;
      example     = "https://share.example.com";
      description = ''
        Public URL ProjectSend is reached at (must include the scheme).
        Used to build share/download links and password-reset emails, so it
        must match whatever Caddy (or other reverse proxy) fronts this with.
      '';
    };

    port = lib.mkOption {
      type        = lib.types.port;
      default     = 8081;
      description = "Loopback port the app container's HTTP port is published on. Point a reverse proxy here.";
    };

    dataDir = lib.mkOption {
      type        = lib.types.path;
      default     = "/var/lib/projectsend";
      description = "Directory holding uploaded files (storage/) and the MySQL data directory.";
    };

    secretsFile = lib.mkOption {
      type        = lib.types.str;
      default     = "/etc/projectsend/secrets.env";
      description = ''
        Path to an env file (root:root, chmod 600), NOT managed by Nix, providing:
          DB_PASSWORD, MYSQL_PASSWORD   - required, must be identical to each other
          MYSQL_ROOT_PASSWORD           - required
          ADMIN_EMAIL, ADMIN_PASSWORD   - optional, creates the first admin account
                                           (ignored after that account exists)
          MAIL_USERNAME, MAIL_PASSWORD  - optional, SMTP credentials for share-link
                                           and notification emails (only read when
                                           `mail.host` is set)
      '';
    };

    dbName = lib.mkOption { type = lib.types.str; default = "projectsend"; };
    dbUser = lib.mkOption { type = lib.types.str; default = "projectsend"; };

    mail = {
      host = lib.mkOption {
        type        = lib.types.str;
        default     = "";
        description = ''
          SMTP host used to send share-link and notification emails.
          Left empty (default), ProjectSend has no mailer configured, so
          sharing a folder by email won't actually deliver anything.
        '';
      };
      port = lib.mkOption {
        type    = lib.types.port;
        default = 587;
      };
      fromAddress = lib.mkOption {
        type        = lib.types.str;
        default     = "";
        example     = "share@example.com";
        description = "From address for outgoing mail. Required when mail.host is set.";
      };
    };

    appImageTag   = lib.mkOption { type = lib.types.str; default = "2"; };
    mysqlImageTag = lib.mkOption { type = lib.types.str; default = "8.4"; };
    redisImageTag = lib.mkOption { type = lib.types.str; default = "7-alpine"; };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = cfg.mail.host == "" || cfg.mail.fromAddress != "";
      message   = "services.projectsend.mail.fromAddress must be set when mail.host is set";
    }];

    virtualisation.podman.enable = true;
    virtualisation.oci-containers.backend = "podman";

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root -"
      "d ${cfg.dataDir}/storage 0750 root root -"
      "d ${cfg.dataDir}/mysql 0700 root root -"
    ];

    systemd.services.init-projectsend-network = {
      description = "Create podman network for ProjectSend containers";
      after       = [ "network.target" ];
      wantedBy    = [ "multi-user.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        ${pkgs.podman}/bin/podman network exists projectsend || \
          ${pkgs.podman}/bin/podman network create projectsend
      '';
    };

    virtualisation.oci-containers.containers = {
      projectsend-db = {
        image     = "mysql:${cfg.mysqlImageTag}";
        autoStart = true;
        environment = {
          MYSQL_DATABASE = cfg.dbName;
          MYSQL_USER     = cfg.dbUser;
        };
        environmentFiles = [ cfg.secretsFile ];  # MYSQL_PASSWORD, MYSQL_ROOT_PASSWORD
        volumes      = [ "${cfg.dataDir}/mysql:/var/lib/mysql" ];
        extraOptions = [ "--network=projectsend" ];
      };

      projectsend-redis = {
        image        = "redis:${cfg.redisImageTag}";
        autoStart    = true;
        extraOptions = [ "--network=projectsend" ];
      };

      projectsend-app = {
        image     = "projectsend/projectsend:${cfg.appImageTag}";
        autoStart = true;
        environment = {
          APP_URL          = cfg.appUrl;
          APP_ENV          = "production";
          APP_DEBUG        = "false";
          DB_CONNECTION    = "mysql";
          DB_HOST          = "projectsend-db";
          DB_PORT          = "3306";
          DB_DATABASE      = cfg.dbName;
          DB_USERNAME      = cfg.dbUser;
          REDIS_HOST       = "projectsend-redis";
          CACHE_STORE      = "redis";
          SESSION_DRIVER   = "redis";
          QUEUE_CONNECTION = "redis";
          # Only Caddy can reach this container (loopback-only port binding
          # below), so trusting every proxy here is safe.
          TRUSTED_PROXIES  = "*";
        } // lib.optionalAttrs (cfg.mail.host != "") {
          MAIL_MAILER       = "smtp";
          MAIL_HOST         = cfg.mail.host;
          MAIL_PORT         = toString cfg.mail.port;
          MAIL_FROM_ADDRESS = cfg.mail.fromAddress;
        };
        # DB_PASSWORD (must equal projectsend-db's MYSQL_PASSWORD), and
        # optionally ADMIN_EMAIL/ADMIN_PASSWORD/MAIL_USERNAME/MAIL_PASSWORD.
        environmentFiles = [ cfg.secretsFile ];
        volumes      = [ "${cfg.dataDir}/storage:/var/www/html/storage" ];
        ports        = [ "127.0.0.1:${toString cfg.port}:80" ];
        extraOptions = [ "--network=projectsend" ];
        dependsOn    = [ "projectsend-db" "projectsend-redis" ];
      };
    };
  };
}
