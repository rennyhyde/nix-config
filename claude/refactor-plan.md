# Refactor: Wolfgang-style modular nix-darwin config

## Status: In progress (refactor/wolfgang branch)

---

## What changed from the flat layout

The original config was three files: `flake.nix`, `configuration.nix`, `home.nix`.
The refactor splits concerns into a `modules/` tree:

```
modules/
├── darwin/
│   ├── default.nix              ← darwinSystem wiring (home-manager, inputs, modules list)
│   ├── _common/default.nix      ← shared Darwin: lix, nixpkgs, nix settings
│   └── rny-macbook/
│       ├── configuration.nix    ← Homebrew casks, fonts, login items, users, stateVersion
│       └── system.nix           ← macOS defaults (dock, finder, keyboard, trackpad)
├── nixos/
│   ├── default.nix              ← skeleton + instructions for adding homelab machines
│   └── _common/default.nix     ← shared NixOS: SSH hardening, GC, common packages
├── home/
│   └── galac/
│       ├── default.nix          ← home-manager entrypoint (imports all dots, packages)
│       ├── git.nix              ← programs.git
│       └── vscode.nix           ← programs.vscode
└── dots/
    ├── zsh/default.nix          ← programs.zsh (aliases, plugins, nixwork alias)
    ├── ghostty/default.nix      ← xdg.configFile."ghostty/config"
    ├── nvim/default.nix         ← programs.neovim (binary only; ~/.config/nvim/ untouched)
    ├── tmux/default.nix         ← programs.tmux
    └── starship/default.nix     ← programs.starship
```

---

## How it wires together

```
flake.nix
  └─ import ./modules/darwin { inherit inputs ... }
       └─ modules/darwin/default.nix  (nix-darwin.lib.darwinSystem)
            ├─ ./_common
            ├─ ./rny-macbook/configuration.nix
            ├─ ./rny-macbook/system.nix
            ├─ darwin-login-items module
            └─ home-manager module
                 └─ home-manager.users.galac = import ../home/galac
                      └─ home/galac/default.nix
                           ├─ dots/zsh, dots/ghostty, dots/nvim, dots/tmux, dots/starship
                           ├─ home/galac/git.nix
                           └─ home/galac/vscode.nix
```

---

## Adding a new macOS machine

1. Create `modules/darwin/<hostname>/configuration.nix` (Homebrew, fonts, users, stateVersion)
2. Create `modules/darwin/<hostname>/system.nix` (macOS defaults)
3. Add a new output in `modules/darwin/default.nix` following the `rny-macbook` pattern
4. Register it in `flake.nix` as `darwinConfigurations."<hostname>"`

---

## Adding a NixOS homelab machine

1. Create `modules/nixos/<hostname>/configuration.nix`
   - Import `./_common`
   - Add machine-specific hardware, services, users
2. Add `nixosConfigurations."<hostname>"` to `flake.nix` outputs:
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
3. `home/galac/default.nix` already sets `homeDirectory` to `/home/galac` on Linux.
4. All `dots/*` modules work unchanged on NixOS.
5. Add `inputs.home-manager` to `flake.nix` inputs if not already there (it is).

---

## Dotfile management explained

Each `dots/<program>/default.nix` is a standalone home-manager module.

| Program  | Method                                | File written by Nix          |
|----------|---------------------------------------|------------------------------|
| zsh      | `programs.zsh.*`                      | `~/.zshrc`                   |
| starship | `programs.starship.*`                 | `~/.config/starship.toml`    |
| tmux     | `programs.tmux.*`                     | `~/.config/tmux/tmux.conf`   |
| ghostty  | `xdg.configFile."ghostty/config"`     | `~/.config/ghostty/config`   |
| neovim   | `programs.neovim` (binary only)       | —  (`~/.config/nvim/` manual)|

**Ghostty** has no native home-manager module yet, so the config is written verbatim via
`xdg.configFile`. To update Ghostty settings, edit `modules/dots/ghostty/default.nix`
and rebuild.

**Neovim** is intentionally minimal — `programs.neovim.enable` installs the binary and
adds `vi`/`vim` aliases, but leaves `~/.config/nvim/` alone for manual editing. When you
want fully-declarative plugin management, use the `nixvim` flake input (see Wolfgang's
`modules/dots/nvim/` for reference).

---

## Rebuild command

```bash
sudo darwin-rebuild switch --flake /etc/nix-darwin#rny-macbook
# or just:
rebuild   # (shell alias)
```

Run `nixwork` to open a 4-pane tmux session with the key config files.

---

## Next steps (optional)

- [ ] Manage existing `~/.config/nvim/` declaratively via `programs.neovim.plugins` or nixvim
- [ ] Add more Ghostty/tmux config options to their respective dot modules
- [ ] Add a NixOS homelab machine using the skeleton in `modules/nixos/`
- [ ] Add `agenix` for encrypted secrets (SSH keys, tokens) once you have secrets to protect
- [ ] Explore `flake-parts` if you add more than 2-3 machines (reduces flake.nix boilerplate)
