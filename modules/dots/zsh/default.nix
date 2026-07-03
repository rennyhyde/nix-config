{ pkgs, ... }:
{
  programs.zsh = {
    enable = true;
    autocd = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      ls      = "eza --icons";
      ll      = "eza -l --icons --git";
      la      = "eza -la --icons --git";
      cat     = "bat";
      grep    = "rg";
      rebuild = "sudo darwin-rebuild switch --flake /etc/nix-darwin#rny-macbook";

      # Open a 4-pane tmux workspace for editing the nix config
      # nixwork = ''
      #   if tmux has-session -t nixdarwin 2>/dev/null; then
      #     tmux attach-session -t nixdarwin
      #   else
      #     tmux new-session -d -s nixdarwin -c /etc/nix-darwin \; \
      #     send-keys "nvim flake.nix" Enter \; \
      #     split-window -h -c /etc/nix-darwin \; \
      #     send-keys "nvim modules/machines/darwin/rny-macbook/configuration.nix" Enter \; \
      #     split-window -v -c /etc/nix-darwin \; \
      #     select-pane -t 0 \; \
      #     split-window -v -c /etc/nix-darwin \; \
      #     send-keys "nvim modules/home/galac/default.nix" Enter \; \
      #     select-pane -t 0 \; \
      #     attach-session -t nixdarwin
      #   fi
      # '';
    };

    initContent = ''
      export EDITOR=nano
    '';
  };

  programs.fzf.enable = true;
}
