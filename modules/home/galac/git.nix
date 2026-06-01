{ ... }:
{
  programs.git = {
    enable = true;
    settings.user.name  = "Renny Hyde";
    settings.user.email = "rennyhyde@protonmail.com";
    settings = {
      init.defaultBranch = "main";
    };
  };
}