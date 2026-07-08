{ config, pkgs, lib, ... }:
let
  cfg = config.services.syncthing-users;
  n   = builtins.length cfg.instances;
in {
  # Multi-user Syncthing — one systemd service per user.
  #
  # Usage in a machine's configuration.nix:
  #   services.syncthing-users = {
  #     enable    = true;
  #     instances = [
  #       { user = "alice"; guiPort = 8384; }
  #       { user = "bob";   guiPort = 8385; }
  #     ];
  #   };
  #
  # After first rebuild, open each instance's GUI and set its P2P listen
  # address (Settings → Connections) to avoid port conflicts:
  #   instance 0 → tcp://0.0.0.0:22000  (default, no change needed)
  #   instance 1 → tcp://0.0.0.0:22001
  #   instance N → tcp://0.0.0.0:2200N
  # This module opens those ports in the firewall automatically.

  options.services.syncthing-users = {
    enable = lib.mkEnableOption "Per-user Syncthing instances";

    instances = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          user    = lib.mkOption { type = lib.types.str; };
          guiPort = lib.mkOption { type = lib.types.port; };
        };
      });
      default     = [];
      description = "One entry per user. guiPort is the localhost port Caddy will proxy.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services = lib.listToAttrs (map (inst: {
      name  = "syncthing-${inst.user}";
      value = {
        description = "Syncthing for ${inst.user}";
        wantedBy    = [ "multi-user.target" ];
        after       = [ "network.target" ];
        environment.STNOUPGRADE = "1";
        serviceConfig = {
          User              = inst.user;
          ExecStart         = "${pkgs.syncthing}/bin/syncthing serve --no-browser --no-restart --logflags=0 --gui-address=127.0.0.1:${toString inst.guiPort} --config=/home/${inst.user}/.config/syncthing --data=/home/${inst.user}/.local/share/syncthing";
          Restart           = "on-failure";
          RestartSec        = "10s";
          SuccessExitStatus = "3 4";
        };
      };
    }) cfg.instances);

    # Ports 22000..22000+n-1 for P2P sync connections.
    # Configure each instance's listen address in its GUI to match.
    networking.firewall.allowedTCPPortRanges = [{ from = 22000; to = 22000 + n - 1; }];
    networking.firewall.allowedUDPPortRanges = [{ from = 22000; to = 22000 + n - 1; }];

    environment.systemPackages = [ pkgs.syncthing ];
  };
}
