{ pkgs, ... }: {
  home.username = "galac";
  home.homeDirectory =
    if pkgs.stdenv.hostPlatform.isDarwin then "/Users/galac" else "/home/galac";
  home.stateVersion = "25.11";
  programs.home-manager.enable = true;

  imports = [
    ../../dots/zsh
    ../../dots/ghostty
    ../../dots/nvim
    ../../dots/tmux
    ../../dots/starship
    ./git.nix
    ./vscode.nix
  ];

  # User-only packages — programs managed by dots modules (neovim, tmux) are omitted here
  home.packages = with pkgs; [
    ripgrep
    fd
    bat
    eza
    fzf
    htop
    tree

    # Dev tools
    rustup
    faust
  ];
}