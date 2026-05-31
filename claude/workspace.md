# nix-darwin Workspace

A 4-panel layout with the three flake files open in neovim plus a free terminal, all rooted in `/etc/nix-darwin`.

```
┌─────────────────────┬─────────────────────┐
│  nvim flake.nix     │  nvim config.nix    │
│                     │                     │
├─────────────────────┼─────────────────────┤
│  nvim home.nix      │  terminal           │
│                     │                     │
└─────────────────────┴─────────────────────┘
```

---

## Option A — tmux (recommended)

tmux sessions survive disconnects, can be reattached from any Ghostty window, and are fully scriptable. This is the standard approach for a persistent dev layout.

### Install tmux

Add to `home.packages` in `home.nix`:

```nix
home.packages = with pkgs; [
  # ... existing packages ...
  tmux
];
```

Then `rebuild`.

### Shell alias

Add to `shellAliases` in `home.nix`:

```nix
shellAliases = {
  # ... existing aliases ...
  nixwork = ''
    tmux new-session -d -s nixdarwin -c /etc/nix-darwin \; \
      send-keys "nvim flake.nix" Enter \; \
      split-window -h -c /etc/nix-darwin \; \
      send-keys "nvim configuration.nix" Enter \; \
      select-pane -t 0 \; \
      split-window -v -c /etc/nix-darwin \; \
      send-keys "nvim home.nix" Enter \; \
      select-pane -t 1 \; \
      split-window -v -c /etc/nix-darwin \; \
      select-pane -t 0 \; \
      attach-session -t nixdarwin
  '';
};
```

After `rebuild`, run `nixwork` from any terminal. If the session already exists, reattach with:

```bash
tmux attach -t nixdarwin
```

### tmux basics

| Action | Default key |
|--------|------------|
| Prefix | `Ctrl+b` |
| Move between panes | `Ctrl+b` then arrow keys |
| Zoom a pane to full screen | `Ctrl+b z` (again to unzoom) |
| Detach (session stays alive) | `Ctrl+b d` |
| List sessions | `tmux ls` |
| Kill session | `tmux kill-session -t nixdarwin` |

### Optional: vim-style pane navigation

Create `~/.config/tmux/tmux.conf`:

```
# Remap prefix to Ctrl+a (less finger strain)
unbind C-b
set-option -g prefix C-a
bind-key C-a send-prefix

# Vim-style pane switching (no prefix needed)
bind -n C-h select-pane -L
bind -n C-l select-pane -R
bind -n C-k select-pane -U
bind -n C-j select-pane -D

# True color support (needed for Ghostty + neovim themes)
set -g default-terminal "tmux-256color"
set -ag terminal-overrides ",xterm-256color:RGB"

# Start pane/window numbering at 1 (easier keyboard reach)
set -g base-index 1
set -g pane-base-index 1

# Increase scrollback
set -g history-limit 10000
```

> **Conflict warning:** `C-h/j/k/l` for tmux pane nav will intercept the same keys inside neovim unless you configure neovim to forward them through. The `vim-tmux-navigator` plugin (`christoomey/vim-tmux-navigator`) handles this transparently — install it in both tmux.conf and neovim.

---

## Option B — Ghostty native splits (current setup)

Ghostty splits work well interactively but **cannot be scripted** from a shell command — there's no CLI flag to open a window with a predefined layout. 

If you want to keep using native splits without tmux, the only option is to record a macro in something like Hammerspoon or Raycast that sends the Ghostty split keybindings in sequence. This is fragile and timing-dependent.

**Bottom line:** for a reproducible, one-command layout, tmux is the right tool.
