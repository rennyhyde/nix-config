# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A nix-darwin + home-manager flake managing an Apple Silicon Mac (`rny-macbook`) and NixOS homelab machines (currently `lovefield`). User is `galac` on all machines.

## Apply the configuration

```bash
# macOS (shell alias `rebuild` also works)
sudo darwin-rebuild switch --flake /etc/nix-darwin#rny-macbook

# NixOS — on the machine itself
sudo nixos-rebuild switch --flake /etc/nixos#lovefield

# NixOS — deployed remotely from the Mac
nixos-rebuild switch --flake /etc/nix-darwin#lovefield --target-host galac@<ip>
```

On lovefield the repo is cloned to `/etc/nixos`. Updates: `cd /etc/nixos && git pull && sudo nixos-rebuild switch --flake /etc/nixos#lovefield`.

## Module structure

```
flake.nix
modules/
├── machines/
│   ├── darwin/
│   │   ├── default.nix               ← darwinSystem wiring (modules list, home-manager)
│   │   ├── _common/default.nix       ← shared: Lix, nixpkgs settings, allowUnfree
│   │   └── rny-macbook/
│   │       ├── configuration.nix     ← Homebrew casks, fonts, login items, users, stateVersion
│   │       └── system.nix            ← macOS defaults (dock, finder, keyboard, trackpad)
│   └── nixos/
│       ├── default.nix               ← instructions for adding homelab machines
│       ├── _common/default.nix       ← shared NixOS: SSH, GC, common packages, timezone
│       └── lovefield/
│           ├── configuration.nix     ← MSI GF63 laptop server
│           └── hardware-configuration.nix
├── home/
│   └── galac/
│       ├── default.nix               ← home-manager entrypoint; homeDirectory auto-set per platform
│       ├── git.nix                   ← programs.git
│       └── vscode.nix                ← programs.vscode
└── dots/
    ├── zsh/default.nix               ← programs.zsh (aliases, plugins)
    ├── ghostty/default.nix           ← xdg.configFile."ghostty/config"
    ├── nvim/default.nix              ← programs.neovim (binary only; ~/.config/nvim/ unmanaged)
    ├── tmux/default.nix              ← programs.tmux
    └── starship/default.nix          ← programs.starship
```

## Module wiring

```
flake.nix
  ├─ import ./modules/machines/darwin { inherit inputs ... }
  │    └─ machines/darwin/default.nix  (nix-darwin.lib.darwinSystem)
  │         ├─ ./_common
  │         ├─ ./rny-macbook/configuration.nix
  │         ├─ ./rny-macbook/system.nix
  │         └─ home-manager → home-manager.users.galac = import ../../home/galac
  │                                ├─ dots/{zsh,ghostty,nvim,tmux,starship}
  │                                ├─ home/galac/git.nix
  │                                └─ home/galac/vscode.nix
  └─ nixosConfigurations."lovefield"  (nixpkgs.lib.nixosSystem)
       ├─ ./modules/machines/nixos/_common
       ├─ ./modules/machines/nixos/lovefield/configuration.nix
       └─ home-manager → home-manager.users.galac = import ./modules/home/galac
```

## Adding a NixOS homelab machine

See `modules/machines/nixos/default.nix` for the full template. Summary:

1. Create `modules/machines/nixos/<hostname>/configuration.nix` and `hardware-configuration.nix`
2. Register in `flake.nix` outputs:
   ```nix
   nixosConfigurations."<hostname>" = nixpkgs.lib.nixosSystem {
     system = "x86_64-linux";
     specialArgs = { inherit inputs; };
     modules = [
       ./modules/machines/nixos/_common
       ./modules/machines/nixos/<hostname>/configuration.nix
       home-manager.nixosModules.home-manager
       {
         home-manager.useGlobalPkgs    = true;
         home-manager.useUserPackages  = true;
         home-manager.extraSpecialArgs = { inherit inputs; };
         home-manager.users.galac      = import ./modules/home/galac;
       }
     ];
   };
   ```
3. `home/galac/default.nix` auto-sets `homeDirectory = "/home/galac"` on Linux. All `dots/*` work unchanged on NixOS.

## Key conventions

- **Lix**: `machines/darwin/_common/default.nix` sets `nix.package = pkgs.lix`.
- **nixpkgs channel**: `nixpkgs-unstable` for Darwin; NixOS machines use the same input.
- **Homebrew**: `onActivation.cleanup = "zap"` — anything not listed in `homebrew.casks` is removed on rebuild.
- **System vs user packages**: CLI tools go in `home.packages` (`home/galac/default.nix`). Global tools go in `environment.systemPackages` (`_common/default.nix`).
- **SSH defaults**: `machines/nixos/_common` sets `PasswordAuthentication = false` and `PermitRootLogin = "no"`. Override per-machine with `lib.mkForce` (lovefield does this).
- **Dotfile methods**: Programs with home-manager support use `programs.*`. Programs without native support (Ghostty) use `xdg.configFile."<path>"`.

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
