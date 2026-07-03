{ pkgs, lib, ... }:
{
  programs.vscode = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
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
    };
  };
}