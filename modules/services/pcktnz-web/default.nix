{ config, pkgs, lib, ... }:
let
  cfg = config.services.pcktnz-web;
  caddyCfg = config.services.caddy-server;
in {
  # pcktnz-web: personal site (Rust / Leptos SSR + wasm hydration on Axum).
  #
  # This is a DEV deployment: the binary is built by hand on lovefield from a
  # git checkout (not by Nix), and this module only runs it and puts it behind
  # Caddy. It is meant to be LAN/VPN-only — expose it with internalOnly and do
  # NOT add its hostname to services.cloudflare-dyndns.domains.
  #
  # One-time setup on lovefield (full runbook: lovefield readme.md, "pcktnz-web"):
  #   git clone https://git.audioboss.win/galac/pcktnz-web <srcDir>   # as galac
  #   cd <srcDir> && git lfs pull
  #   nix develop -c cargo leptos build --release
  #   sudo systemctl restart pcktnz-web
  # Later updates: ./deploy/lovefield.sh from inside the checkout.
  #
  # The unit is skipped (not failed) while <srcDir>/target/release/server is
  # missing, so a rebuild of lovefield before the first site build is harmless.
  #
  # Usage in a machine's configuration.nix:
  #   services.pcktnz-web.enable = true;
  #   services.caddy-server.expose = [
  #     { subdomain = "pcktnz"; port = config.services.pcktnz-web.port; internalOnly = true; }
  #   ];

  options.services.pcktnz-web = {
    enable = lib.mkEnableOption "pcktnz-web dev server (built by hand from a git checkout)";

    port = lib.mkOption {
      type        = lib.types.port;
      default     = 3100;
      description = "Loopback port the site listens on. 3000 is taken by AdGuard Home's web UI.";
    };

    srcDir = lib.mkOption {
      type        = lib.types.path;
      default     = "/srv/pcktnz-web";
      description = ''
        Git checkout of pcktnz-web. Owned by `owner` so the build can run as a
        normal user. The service reads target/release/server, target/site/,
        content/ from here.
      '';
    };

    owner = lib.mkOption {
      type        = lib.types.str;
      default     = "galac";
      description = "User that owns srcDir and runs the builds.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Checkout dir, created once; the clone/pull and build happen as `owner`.
    systemd.tmpfiles.rules = [
      "d ${cfg.srcDir} 0755 ${cfg.owner} users -"
    ];

    # git-lfs: the content/ media is in LFS, and `git lfs pull` must work on
    # lovefield. (The build toolchain itself comes from the repo's flake, via
    # `nix develop` — nothing else needs installing system-wide.)
    environment.systemPackages = [ pkgs.git-lfs ];

    systemd.services.pcktnz-web = {
      description = "pcktnz-web dev server (Leptos SSR)";
      wantedBy    = [ "multi-user.target" ];
      after       = [ "network.target" ];
      # Don't crash-loop before the first `cargo leptos build --release`.
      unitConfig.ConditionPathExists = "${cfg.srcDir}/target/release/server";

      # No Cargo.toml metadata is read at runtime in a deployed binary, so the
      # leptos config comes from env vars (cargo-leptos sets the same ones
      # under `watch`). Everything the site writes (SQLite, resized images)
      # goes to the unit's StateDirectory; the checkout is read-only to it.
      environment = {
        LEPTOS_OUTPUT_NAME  = "site";
        LEPTOS_SITE_ROOT    = "${cfg.srcDir}/target/site";
        LEPTOS_SITE_PKG_DIR = "pkg";
        LEPTOS_SITE_ADDR    = "127.0.0.1:${toString cfg.port}";
        LEPTOS_ENV          = "PROD";
        CONTENT_DIR         = "${cfg.srcDir}/content/nodes";
        COURSEWORK_DIR      = "${cfg.srcDir}/content/coursework";
        DATABASE_URL        = "sqlite:///var/lib/pcktnz-web/site.db?mode=rwc";
        MEDIA_CACHE_DIR     = "/var/lib/pcktnz-web/media-cache";
        RUST_LOG            = "info";
      };

      serviceConfig = {
        Type             = "simple";
        ExecStart        = "${cfg.srcDir}/target/release/server";
        WorkingDirectory = cfg.srcDir;
        Restart          = "always";
        RestartSec       = "5s";
        DynamicUser      = true;
        StateDirectory   = "pcktnz-web";
        # Hardening: only the state dir is writable; the checkout is readable
        # through ProtectSystem=strict's read-only view of the filesystem.
        ProtectSystem    = "strict";
        ProtectHome      = true;
        PrivateTmp       = true;
        NoNewPrivileges  = true;
      };
    };

    # The Caddy vhost itself comes from services.caddy-server.expose in the
    # machine config (so internalOnly gating stays in one place); nothing to
    # add here. This assertion just catches enabling the site with no proxy.
    assertions = [{
      assertion = caddyCfg.enable;
      message   = "services.pcktnz-web is only reachable through services.caddy-server; enable it and add an expose entry.";
    }];
  };
}
