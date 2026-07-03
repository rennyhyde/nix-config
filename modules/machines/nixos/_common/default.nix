{ pkgs, ... }:
{
  # ── Nix daemon ────────────────────────────────────────────────────────────
  nixpkgs.config.allowUnfree = true;

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users          = [ "root" "@wheel" ];
      auto-optimise-store    = true;
    };
    gc = {
      automatic = true;
      dates     = "weekly";
      options   = "--delete-older-than 14d";
    };
  };

  # ── Common packages on every machine ─────────────────────────────────────
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    htop
    tmux
    rsync
    ripgrep
    eza
    jq
  ];

  # ── SSH: key-only, no root login ──────────────────────────────────────────
  services.openssh = {
    enable                 = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin        = "no";
  };

  # ── Shell ─────────────────────────────────────────────────────────────────
  programs.zsh.enable = true;

  # ── Time ──────────────────────────────────────────────────────────────────
  time.timeZone = "America/Chicago"; # override per-machine as needed
}
