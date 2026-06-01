{ pkgs, ... }:
{
  environment.systemPath = [
  	"/opt/homebrew/bin"
  	"/opt/homebrew/sbin"
 	  "/Library/TeX/texbin"
  ];

  environment.loginItems = {
    enable = true;
    items = [
      "/Applications/LinearMouse.app"
      "/Users/galac/Applications/Flux.app"
      "/Applications/ProtonVPN.app"
    ];
  };

  ### Homebrew
  homebrew = {
    enable = true;
    onActivation.autoUpdate = true;
    onActivation.cleanup = "zap";     # remove anything not listed here
    casks = [
      "firefox"
      "ghostty"
      "signal"
      "spotify"
      "libreoffice"
      "affinity"
      "reaper"
      "claude"
      "claude-code"
      "arduino-ide"
      "autodesk-fusion"
      "kicad"
      "vlc"
      "audacity"
      "discord"
      "google-chrome" # Just in case
      "yubico-authenticator"
      "protonvpn"
      "proton-drive"
      "proton-mail"
      "linearmouse"   # Fixes mouse scrolling direction and trackpad
      "bitwarden"
      "anytype"
      "figma"
      "rekordbox"
      "mixxx"
      "steam"
      "darktable"
      "obsidian"
      "zettlr"
      "zotero"
      "mactex"
      "petrichor"

      # Not on homebrew or nix:
      #
      # Serato DJ Pro
    ];
  };

  system.stateVersion = 5;

  users.users.galac = {
     home = "/Users/galac";
  };

  system.primaryUser = "galac";

  fonts.packages = with pkgs; [
    nerd-fonts._0xproto
    source-code-pro
  ];
}