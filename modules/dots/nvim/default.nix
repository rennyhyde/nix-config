{ ... }:
{
  # home-manager installs neovim and wires it into the user profile.
  # ~/.config/nvim/ is intentionally left unmanaged so the existing
  # config can be edited freely. Migrate plugins inline here (via
  # programs.neovim.plugins) when ready to go fully declarative.
  programs.neovim = {
    enable = true;
    vimAlias = true;
    viAlias = true;
    withRuby = false;
    withPython3 = false;
  };
}
