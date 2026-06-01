{ ... }: {
  xdg.configFile."ghostty/config".text = ''
    font-family = 0xProto Nerd Font
    font-size = 14
    theme = dark:catppuccin-mocha,light:catppuccin-latte
    background-opacity = 0.95
    shell-integration = zsh
  '';
}