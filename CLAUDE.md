# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A nix-darwin + home-manager flake for an Apple Silicon Mac (`rny-macbook`, user `galac`). It manages system packages, macOS defaults, Homebrew casks, and the user environment in a single flake.

## Apply the configuration

```bash
sudo darwin-rebuild switch --flake /etc/nix-darwin#rny-macbook
```

This is also available as the shell alias `rebuild`.

## File layout

| File | Purpose |
|------|---------|
| `flake.nix` | Inputs (nixpkgs-unstable, nix-darwin, home-manager, darwin-login-items) and the single `darwinConfigurations."rny-macbook"` output |
| `configuration.nix` | System-level settings: system packages, macOS defaults (`system.defaults.*`), Homebrew casks, fonts, login items, Lix as the Nix implementation |
| `home.nix` | User-level settings via home-manager: user packages, zsh (aliases, plugins), VSCode profile, git config, starship prompt |
| `one-time-scripts/` | Bootstrap scripts that run once on a fresh install (not managed by Nix) |

## Key conventions

- **System vs user packages**: CLI tools go in `home.packages` (home.nix); only truly global tools go in `environment.systemPackages` (configuration.nix).
- **Homebrew casks**: `onActivation.cleanup = "zap"` — anything not listed in `homebrew.casks` will be **removed** on the next rebuild.
- **Nix implementation**: Lix (`pkgs.lix`) is used instead of upstream Nix.
- **nixpkgs channel**: `nixpkgs-unstable` — package names and options may differ from the stable channel.
- **Architecture**: `aarch64-darwin` (Apple Silicon). Use `x86_64-darwin` for Intel.
