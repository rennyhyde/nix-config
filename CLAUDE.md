# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A nix-darwin + home-manager flake for an Apple Silicon Mac (`rny-macbook`, user `galac`) and future NixOS homelab machines. It manages system packages, macOS defaults, Homebrew casks, dotfiles, and the user environment in a single flake. NixOS machine support (starting with `lovefield`) is the current next step.

## Apply the configuration

```bash
# macOS (alias also available as `rebuild`)
sudo darwin-rebuild switch --flake /etc/nix-darwin#rny-macbook

# NixOS homelab machine (once added)
sudo nixos-rebuild switch --flake /etc/nix-darwin#<hostname>
# or remotely:
nixos-rebuild switch --flake /etc/nix-darwin#<hostname> --target-host galac@<ip>
```

## Module structure

```
flake.nix                         ← inputs + darwinConfigurations outputs (nixosConfigurations to be added)
modules/
├── darwin/
│   ├── default.nix               ← darwinSystem wiring (modules list, home-manager)
│   ├── _common/default.nix       ← shared: Lix, nixpkgs settings, allowUnfree
│   └── rny-macbook/
│       ├── configuration.nix     ← Homebrew casks, fonts, login items, users, stateVersion
│       └── system.nix            ← macOS defaults (dock, finder, keyboard, trackpad)
├── nixos/
│   ├── default.nix               ← skeleton with instructions for adding homelab machines
│   └── _common/default.nix      ← shared NixOS: SSH hardening, GC, common packages, timezone
├── home/
│   └── galac/
│       ├── default.nix           ← home-manager entrypoint; homeDirectory auto-set per platform
│       ├── git.nix               ← programs.git
│       └── vscode.nix            ← programs.vscode
└── dots/
    ├── zsh/default.nix           ← programs.zsh (aliases, plugins, nixwork alias)
    ├── ghostty/default.nix       ← xdg.configFile."ghostty/config"
    ├── nvim/default.nix          ← programs.neovim (binary only; ~/.config/nvim/ unmanaged)
    ├── tmux/default.nix          ← programs.tmux
    └── starship/default.nix      ← programs.starship
```

## Module wiring

```
flake.nix
  └─ import ./modules/darwin { inherit inputs ... }
       └─ modules/darwin/default.nix  (nix-darwin.lib.darwinSystem)
            ├─ ./_common
            ├─ ./rny-macbook/configuration.nix
            ├─ ./rny-macbook/system.nix
            └─ home-manager module → home-manager.users.galac = import ../home/galac
                                          ├─ dots/{zsh,ghostty,nvim,tmux,starship}
                                          ├─ home/galac/git.nix
                                          └─ home/galac/vscode.nix
```

## Adding a NixOS homelab machine

See `modules/nixos/default.nix` for the full template and comments. Summary:

1. Create `modules/nixos/<hostname>/configuration.nix`:
   - Import `../_common` for shared SSH, GC, common packages
   - Add machine-specific hardware, networking, filesystems, services, users
2. Register in `flake.nix` outputs:
   ```nix
   nixosConfigurations."<hostname>" = inputs.nixpkgs.lib.nixosSystem {
     system = "x86_64-linux";
     specialArgs = { inherit inputs; };
     modules = [
       ./modules/nixos/_common
       ./modules/nixos/<hostname>/configuration.nix
       inputs.home-manager.nixosModules.home-manager
       {
         home-manager.useGlobalPkgs    = true;
         home-manager.useUserPackages  = true;
         home-manager.extraSpecialArgs = { inherit inputs; };
         home-manager.users.galac      = import ./modules/home/galac;
       }
     ];
   };
   ```
3. `home/galac/default.nix` automatically sets `homeDirectory = "/home/galac"` on Linux.
4. All `dots/*` modules work unchanged on NixOS.

**Important**: `nixos/_common` sets `PasswordAuthentication = false` and `PermitRootLogin = "no"`. Override these per-machine if needed (e.g., lovefield allows password auth for a shared user).

## Key conventions

- **Lix**: `darwin/_common/default.nix` sets `nix.package = pkgs.lix` — Lix is used instead of upstream Nix.
- **nixpkgs channel**: `nixpkgs-unstable`. Package names/options may differ from the stable channel.
- **Architecture**: `aarch64-darwin` (Apple Silicon). Change `nixpkgs.hostPlatform` in `_common/default.nix` for Intel.
- **Homebrew**: `onActivation.cleanup = "zap"` — anything not listed in `homebrew.casks` is removed on rebuild.
- **System vs user packages**: CLI tools go in `home.packages` (home/galac/default.nix). Truly global tools go in `environment.systemPackages` (_common/default.nix).
- **Dotfile methods**: Programs with home-manager support use `programs.*`. Programs without (Ghostty) use `xdg.configFile."<path>"`.

## Dotfile management

| Program  | Method                             | File managed by Nix           |
|----------|------------------------------------|-------------------------------|
| zsh      | `programs.zsh.*`                   | `~/.zshrc`                    |
| starship | `programs.starship.*`              | `~/.config/starship.toml`     |
| tmux     | `programs.tmux.*`                  | `~/.config/tmux/tmux.conf`    |
| ghostty  | `xdg.configFile."ghostty/config"`  | `~/.config/ghostty/config`    |
| neovim   | `programs.neovim` (binary only)    | — (`~/.config/nvim/` manual)  |

## Extended notes

See `claude/` for design documents:
- `refactor-plan.md` — the completed Wolfgang-style modular refactor
- `analyze-the-nix-config-wolfgang-reposito-cozy-cocke.md` — deep dive into Wolfgang's config patterns
- `workspace.md` — tmux layout for editing this repo
