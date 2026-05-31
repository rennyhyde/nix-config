# Ghostty Customization

Config file: `~/.config/ghostty/config` (plain text, no extension).  
Ghostty hot-reloads on save — no restart needed for most settings.

## Fonts

`0xProto Nerd Font` is already installed via Nix (`nerd-fonts._0xproto`).

```
font-family = 0xProto Nerd Font Mono
font-size = 14
font-thicken = true          # macOS sub-pixel rendering tweak
```

## Themes

```
theme = catppuccin-mocha
```

List all built-in themes:

```bash
ghostty +list-themes
ghostty +list-themes | grep -i tokyo    # filter
```

Preview in a running terminal: `ghostty +list-themes` is interactive — arrow keys cycle live.

Popular choices for dark environments: `catppuccin-mocha`, `tokyonight`, `gruvbox-dark`, `nord`.

## Transparency & Blur

```
background-opacity = 0.92
background-blur-radius = 20
```

## Window & Padding

```
window-padding-x = 12
window-padding-y = 8
window-decoration = false          # hides the macOS title bar chrome
macos-titlebar-style = hidden      # alternative that keeps the traffic lights
macos-window-shadow = true
```

## Cursor

```
cursor-style = bar                 # block | bar | underline
cursor-style-blink = true
```

## Split keybinds

Ghostty's defaults use `cmd+d` / `cmd+shift+d` / `cmd+opt+↑↓←→`. Override if you prefer vim-style:

```
keybind = ctrl+shift+h=new_split:left
keybind = ctrl+shift+l=new_split:right
keybind = ctrl+shift+j=new_split:down
keybind = ctrl+shift+k=new_split:up
keybind = ctrl+h=goto_split:left
keybind = ctrl+l=goto_split:right
keybind = ctrl+j=goto_split:bottom
keybind = ctrl+k=goto_split:top
```

> **Note:** If you use the tmux workflow (see `workspace.md`), `ctrl+hjkl` will conflict with tmux pane navigation unless you configure tmux's prefix differently. Pick one movement system.

## Shell integration

Ghostty ships its own shell integration. In zsh it's automatic when `programs.zsh.enable = true` in `home.nix`. It enables semantic zones (click to jump between prompts), `cmd+click` on paths, and proper title tracking.

## Full example config

```
font-family = 0xProto Nerd Font Mono
font-size = 14
font-thicken = true

theme = catppuccin-mocha

background-opacity = 0.93
background-blur-radius = 20

window-padding-x = 12
window-padding-y = 8
window-decoration = false
macos-window-shadow = true

cursor-style = bar
cursor-style-blink = true
```
