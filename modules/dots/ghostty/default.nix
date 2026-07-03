{ ... }: {
  xdg.configFile."ghostty/config".text = ''
    term = xterm-256color
    font-family = 0xProto Nerd Font
    font-size = 14
    theme = dark:Catppuccin Mocha,light:Catppuccin Latte
    background-opacity = 1.0
    shell-integration = zsh
  '';
}
