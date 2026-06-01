{
  system.defaults = {
    dock = {
      autohide = false;
      show-recents = false;
      tilesize = 48;
      appswitcher-all-displays = true;
      magnification = false;
      expose-animation-duration = 0.2;
      mineffect = "scale";
      # largesize = 64;
      # TODO: Add persistent apps
    };
    finder = {
      AppleShowAllExtensions = true;
      # ShowPathbar = true;
      FXDefaultSearchScope = "SCcf";   # search current folder by default
    };
   NSGlobalDomain = {
      AppleShowAllFiles = true;
      NSDocumentSaveNewDocumentsToCloud = false;
      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
      NSAutomaticWindowAnimationsEnabled = false;
      "com.apple.mouse.tapBehavior" = 1;
      NSWindowResizeTime = 0.001;
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
    #universalaccess.mouseDriverCursorSize = 1.5; # This one only works if run in the default macos terminal (TODO: why?)
  };
}