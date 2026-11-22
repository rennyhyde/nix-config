{ config, pkgs, lib, ... }:
let
  cfg = config.services.filebrowser-quantum;

  # Paths inside the container. The image's default config location is
  # /home/filebrowser/data/config.yaml; the writable state (SQLite db, cache)
  # lives on its own mount so the read-only config can sit on top of the image.
  configPath = "/home/filebrowser/data/config.yaml";
  stateDir   = "/state";
  filesDir   = "/srv/files";

  configFile = (pkgs.formats.yaml { }).generate "filebrowser-config.yaml" {
    http = {
      # Host networking + loopback bind: only Caddy (same host) can reach it,
      # and FileBrowser sees Caddy's real peer address (127.0.0.1).
      listen            = "127.0.0.1";
      port              = cfg.port;
      baseURL           = "/";
      externalUrl       = cfg.externalUrl;  # used to build share links
      trustProxyHeaders = true;
      trustedProxies    = [ "127.0.0.1/32" "::1/128" ];
    };
    server = {
      cacheDir = "${stateDir}/cache";
      database.path = "${stateDir}/database.sqlite";
      # Group-writable so files stay manageable from the OS by members of the
      # filebrowser group (the files dir is setgid, so new entries inherit it).
      filesystem = {
        createFilePermission      = "664";
        createDirectoryPermission = "775";
      };
      sources = [{
        path = filesDir;
        name = cfg.sourceName;
        config = {
          defaultEnabled   = true;  # new users get this source
          defaultUserScope = "/";   # whole tree; narrow per user in the admin UI
          defaultPermissions = {
            view     = true;
            download = true;
            modify   = true;
            create   = true;
            delete   = true;
          };
        };
      }];
    };
    auth.methods.password = {
      enabled       = true;
      adminUsername = cfg.adminUsername;
      minLength     = 10;
      signup        = false;  # accounts are created by the admin
    };
    # Let every user create share links (password/expiry/upload-only).
    userDefaults.account.permissions.share = true;
    frontend.name = cfg.title;
  };
in {
  # FileBrowser Quantum (https://github.com/gtsteffaniak/filebrowser) — web
  # file manager over a plain directory: per-user logins (password + optional
  # TOTP), uploads from any browser including phones, and share links with
  # password / expiry / download limit / upload-only. Files stay ordinary files
  # on disk. Runs as one podman container (upstream image; nixpkgs only
  # packages the original filebrowser, not the Quantum fork).
  #
  # One-time setup on each machine before enabling:
  #   sudo mkdir -p /etc/filebrowser
  #   sudo tee /etc/filebrowser/secrets.env <<EOF
  #   FILEBROWSER_ADMIN_PASSWORD=<first admin password, 10+ chars>
  #   FILEBROWSER_JWT_TOKEN_SECRET=$(openssl rand -base64 32)
  #   FILEBROWSER_TOTP_SECRET=$(openssl rand -base64 32)
  #   EOF
  #   sudo chmod 600 /etc/filebrowser/secrets.env
  # FILEBROWSER_ADMIN_PASSWORD is re-applied on every start; delete the line
  # after first login if you'd rather change the password in the UI.
  # Never change FILEBROWSER_TOTP_SECRET once users enable 2FA (locks them out).
  #
  # Usage in a machine's configuration.nix:
  #   services.filebrowser-quantum = {
  #     enable      = true;
  #     externalUrl = "https://files.example.com";
  #     dataDir     = "/mnt/storage/filebrowser";
  #   };
  # Then add { subdomain = "files"; port = config.services.filebrowser-quantum.port;
  # rewriteHost = false; } to services.caddy-server.expose (it needs the real
  # Host header) and "files.example.com" to services.cloudflare-dyndns.domains.

  options.services.filebrowser-quantum = {
    enable = lib.mkEnableOption "FileBrowser Quantum web file manager";

    externalUrl = lib.mkOption {
      type        = lib.types.str;
      example     = "https://files.example.com";
      description = "Public URL (with scheme) used in share links. Must match the reverse proxy.";
    };

    port = lib.mkOption {
      type        = lib.types.port;
      default     = 8082;
      description = "Loopback port FileBrowser listens on. Point a reverse proxy here.";
    };

    dataDir = lib.mkOption {
      type        = lib.types.path;
      default     = "/var/lib/filebrowser-quantum";
      description = "Holds files/ (the shared tree) and state/ (SQLite db, thumbnail/archive cache).";
    };

    uid = lib.mkOption {
      type        = lib.types.int;
      default     = 820;
      description = "Fixed UID/GID of the filebrowser user the container runs as (owns everything uploaded).";
    };

    adminUsername = lib.mkOption { type = lib.types.str; default = "admin"; };
    title         = lib.mkOption { type = lib.types.str; default = "Files"; };
    sourceName    = lib.mkOption { type = lib.types.str; default = "files"; };

    secretsFile = lib.mkOption {
      type        = lib.types.str;
      default     = "/etc/filebrowser/secrets.env";
      description = ''
        Env file (root:root, chmod 600), NOT managed by Nix, providing
        FILEBROWSER_ADMIN_PASSWORD, FILEBROWSER_JWT_TOKEN_SECRET and
        FILEBROWSER_TOTP_SECRET.
      '';
    };

    imageTag = lib.mkOption {
      type        = lib.types.str;
      default     = "2.0-stable";
      description = "ghcr.io/gtsteffaniak/filebrowser tag. Pinned to the stable 2.0 line (patch updates on pull).";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.podman.enable = true;
    virtualisation.oci-containers.backend = "podman";

    users.groups.filebrowser.gid = cfg.uid;
    users.users.filebrowser = {
      isSystemUser = true;
      uid          = cfg.uid;
      group        = "filebrowser";
      description  = "FileBrowser Quantum";
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      # setgid: everything created under files/ stays in the filebrowser group
      "d ${cfg.dataDir}/files 2775 filebrowser filebrowser -"
      "d ${cfg.dataDir}/state 0750 filebrowser filebrowser -"
    ];

    virtualisation.oci-containers.containers.filebrowser-quantum = {
      image     = "ghcr.io/gtsteffaniak/filebrowser:${cfg.imageTag}";
      autoStart = true;
      user      = "${toString cfg.uid}:${toString cfg.uid}";
      environment.FILEBROWSER_CONFIG = configPath;
      environmentFiles = [ cfg.secretsFile ];
      volumes = [
        "${configFile}:${configPath}:ro"
        "${cfg.dataDir}/state:${stateDir}"
        "${cfg.dataDir}/files:${filesDir}"
      ];
      extraOptions = [
        "--network=host"
        # The image's healthcheck probes port 80; we listen on cfg.port.
        "--no-healthcheck"
      ];
    };

    # Restart the container when the generated config changes.
    systemd.services.podman-filebrowser-quantum.restartTriggers = [ configFile ];
  };
}
