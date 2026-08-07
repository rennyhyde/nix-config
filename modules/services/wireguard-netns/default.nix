{ config, pkgs, lib, ... }:
let
  cfg = config.services.wireguard-netns;
in
{
  options.services.wireguard-netns = {
    enable = lib.mkEnableOption "isolated network namespace whose only route out is a WireGuard tunnel";

    namespace = lib.mkOption {
      type        = lib.types.str;
      default     = "protonvpn";
      description = "Name of the network namespace to create (visible as /var/run/netns/<name>).";
    };

    configFile = lib.mkOption {
      type        = lib.types.path;
      description = ''
        Path to a raw `wg setconf`-style WireGuard config (NOT a wg-quick config —
        no Address/DNS lines, those are handled separately below). Must contain
        [Interface] PrivateKey and [Peer] PublicKey/Endpoint/AllowedIPs.
      '';
      example = "/etc/proton-vpn/qbittorrent.conf";
    };

    address = lib.mkOption {
      type        = lib.types.str;
      description = "Tunnel address assigned to the wg interface inside the namespace, e.g. \"10.2.0.2/32\".";
    };

    dns = lib.mkOption {
      type        = lib.types.str;
      default     = "1.1.1.1";
      description = "DNS server used for lookups made inside the namespace.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Namespace lifecycle. `before = network.target` so it exists before anything
    # tries to join it.
    systemd.services."netns@" = {
      description = "%I network namespace";
      before = [ "network.target" ];
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
        ExecStart       = "${pkgs.iproute2}/bin/ip netns add %I";
        ExecStop        = "${pkgs.iproute2}/bin/ip netns del %I";
      };
    };

    environment.etc."netns/${cfg.namespace}/resolv.conf".text = "nameserver ${cfg.dns}\n";

    # Creates the wg interface *inside* the namespace (never touches the host's
    # own routing table) and makes it the namespace's only route. If the tunnel
    # goes down, there is nothing else in this namespace to fall back to — that's
    # the kill switch, no iptables DROP rules required.
    systemd.services.${cfg.namespace} = {
      description = "${cfg.namespace} WireGuard interface";
      bindsTo     = [ "netns@${cfg.namespace}.service" ];
      requires    = [ "network-online.target" ];
      after       = [ "netns@${cfg.namespace}.service" "network-online.target" ];
      wantedBy    = [ "multi-user.target" ];
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writers.writeBash "wireguard-netns-up-${cfg.namespace}" ''
          set -e
          ${pkgs.iproute2}/bin/ip link add wg0 type wireguard
          ${pkgs.iproute2}/bin/ip link set wg0 netns ${cfg.namespace}
          ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} address add ${cfg.address} dev wg0
          ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} \
            ${pkgs.wireguard-tools}/bin/wg setconf wg0 ${cfg.configFile}
          ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} link set wg0 up
          ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} link set lo up
          ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} route add default dev wg0
        '';
        ExecStop = pkgs.writers.writeBash "wireguard-netns-down-${cfg.namespace}" ''
          set -e
          ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} route del default dev wg0 || true
          ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} link del wg0 || true
        '';
      };
    };

    environment.systemPackages = [ pkgs.wireguard-tools pkgs.iproute2 ];
  };
}
