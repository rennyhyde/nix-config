{ ... }: {
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    historyLimit = 10000;
    keyMode = "vi";
    extraConfig = ''
      # any options not covered by home-manager options
    '';
  };
}