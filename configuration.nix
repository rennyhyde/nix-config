{ pkgs, ... }:

{
  # Use Lix instead of upstream Nix
  nix.package = pkgs.lix;

  # Required: tells nix-darwin which platform this is
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Allow unfree packages (VSCode, etc.)
  nixpkgs.config.allowUnfree = true;

  # Flakes and the new CLI (already enabled by Lix installer, but declare it here too)
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # System-wide CLI packages (available to all users)
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    #vscode
  ];

  # Use zsh as the default shell
  programs.zsh.enable = true;

  # macOS system preferences
  system.defaults = {
    dock = {
      autohide = false;
      show-recents = false;
      tilesize = 48;
      appswitcher-all-displays = true;
      magnification = false;
      # largesize = 64;
      # TODO: Add persistent apps
    };
    finder = {
      AppleShowAllExtensions = true;
      #ShowPathbar = true;
      FXDefaultSearchScope = "SCcf";   # search current folder by default
    };
   NSGlobalDomain = {
      AppleShowAllFiles = true;
      NSDocumentSaveNewDocumentsToCloud = false;
      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
      "com.apple.mouse.tapBehavior" = 1;
    };
    trackpad.Clicking = true;          # tap to click
    SoftwareUpdate.AutomaticallyInstallMacOSUpdates = false;
    WindowManager = {
      AppWindowGroupingBehavior = true; # Show all windows of a given app at once
    };
    controlcenter = {
      Bluetooth = true;
    };
    finder = {
      AppleShowAllFiles = true;
      FXEnableExtensionChangeWarning = false;
      ShowPathbar = true;
      ShowStatusBar = true;
      _FXSortFoldersFirst = true;
    };
    iCal."first day of week" = "Monday";
    loginwindow = {
      LoginwindowText = "Hiiiii :3";
    };
    # universalaccess.mouseDriverCursorSize = 5.0; # I don't think this works
  };

  # Homebrew — for GUI apps and anything not in nixpkgs
  # nix-darwin installs Homebrew itself if missing, and manages it declaratively
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
