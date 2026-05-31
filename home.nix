{ pkgs, ... }:

{
    home.stateVersion = "25.11";

  # User-only packages
  home.packages = with pkgs; [
    ripgrep
    fd
    bat
    eza
    fzf
    htop
    tree

    ### Dev tools
    # Rust
    rustup

    # Faust
    faust

    # IDE
    neovim
    tmux
  ];

  # Shell — home-manager writes ~/.zshrc from this
  programs.zsh = {
    enable = true;
    autocd = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      ls   = "eza --icons";
      ll   = "eza -l --icons --git";
      la   = "eza -la --icons --git";
      cat  = "bat";
      grep = "rg";
      rebuild = "sudo darwin-rebuild switch --flake /etc/nix-darwin#rny-macbook";
      nixwork = ''
        if tmux has-session -t nixdarwin 2>/dev/null; then
          tmux attach-session -t nixdarwin
        else
          tmux new-session -d -s nixdarwin -c /etc/nix-darwin \; \
          send-keys "nvim flake.nix" Enter \; \
          split-window -h -c /etc/nix-darwin \; \
          send-keys "nvim configuration.nix" Enter \; \
          split-window -v -c /etc/nix-darwin \; \
          select-pane -t 0 \; \
          split-window -v -c /etc/nix-darwin \; \
          send-keys "nvim home.nix" Enter \; \
          select-pane -t 0 \; \
          attach-session -t nixdarwin
        fi
      '';
    };
    # Anything else that isn't covered by nix goes in the initExtra
    initContent = ''
      export EDITOR=nano
    '';
  };

  programs.vscode = {
  enable = true;
  profiles.default.extensions = with pkgs.vscode-extensions; [
    rust-lang.rust-analyzer
    jnoortheen.nix-ide
  ];
  profiles.default.userSettings = {
    "editor.fontSize" = 14;
    "editor.fontFamily" = "'0xproto', monospace";
    "editor.fontLigatures" = true;
    "editor.formatOnSave" = false;
    "editor.tabSize" = 4;
    "workbench.colorTheme" = "Default Dark Modern";
    # "rust-analyzer.check.command" = "clippy";
  };
};

  # Git — home-manager writes ~/.gitconfig from this
  programs.git = {
    enable = true;
    settings.user.name  = "Renny Hyde";
    settings.user.email = "rennyhyde@protonmail.com";
    settings = {
      init.defaultBranch = "main";
    };
  };

  # Starship prompt — home-manager writes ~/.config/starship.toml
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };
}
