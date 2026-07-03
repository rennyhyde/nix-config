{ pkgs, ... }:

{
  # Use Lix instead of upstream Nix
  nix.package = pkgs.lix;

  nixpkgs.hostPlatform = "aarch64-darwin"; # Replace with intel if needed

  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # System-wide CLU packages
  environment.systemPackages = with pkgs; [ 
    git 
    curl 
    wget 
  ];
  
  programs.zsh.enable = true;
}