# Plan: Modularize nix-darwin Config (Wolfgang-style)

## Context

Your current config (`/etc/nix-darwin`) is a clean but monolithic 3-file setup: `flake.nix`, `configuration.nix`, and `home.nix`. Everything lives in those files — Homebrew casks, system defaults, user packages, shell config, and program settings. It works, but as it grows it becomes harder to navigate and reason about.

Wolfgang's `nix-config-wolfgang` is a mature, production-grade example of the opposite philosophy: every concern lives in its own module, dotfiles are fully Nix-managed, and machines are auto-discovered. This plan describes exactly how Wolfgang's approach works and maps it onto a concrete restructuring plan for your config.

---

## Part 1: How Wolfgang's Config Works (In Depth)

### The Flake is Just a Router

Wolfgang's `flake.nix` does almost nothing except declare inputs and delegate to submodules via `flake-parts`. The real logic lives in `./modules/machines/darwin` and `./modules/machines/nixos`. This is intentional: the flake is a thin entrypoint, not a configuration file.

```
flake.nix
  └── imports:
        ./modules/machines/darwin   → flake.darwinConfigurations
        ./modules/machines/nixos    → flake.nixosConfigurations
        ./modules/devshell.nix      → devShells
```

He uses `flake-parts` (a Nix library) to let each imported module *extend* the flake's outputs rather than having one giant `outputs = { ... }` block. You don't need `flake-parts` to start — your current `nix-darwin.lib.darwinSystem` pattern is fine — but it's how he keeps the flake clean.

### Machine Auto-Discovery

In `modules/machines/darwin/default.nix`, Wolfgang uses `builtins.readDir` to scan subdirectories and automatically register any folder that contains a `configuration.nix` as a Darwin host:

```nix
# Pseudocode of the pattern:
let
  machines = builtins.attrNames (builtins.readDir ./.);
  validMachines = builtins.filter
    (name: builtins.pathExists ./${name}/configuration.nix)
    machines;
in
# generate darwinConfigurations.${name} for each
```

This means adding a new Mac is as simple as creating `./modules/machines/darwin/new-machine/configuration.nix`. No editing of the flake or the default.nix.

### The `homeManagerCfg` Factory Function

Inside `modules/machines/darwin/default.nix`, Wolfgang defines a helper function called `homeManagerCfg` that produces a consistent home-manager module for every machine. It handles:
- Which user to configure (`notthebee`)
- What home directory to use (`/Users/notthebee` on Darwin)
- Whether to use `useUserPackages`
- Which extra modules to inject (agenix, nixvim, nix-index-database)
- Importing the shared `dots.nix`

This is the key abstraction. Instead of copy-pasting home-manager boilerplate per machine, you call `homeManagerCfg { userPackages = true; }` and get a fully-configured module back.

### The `_common` Pattern

Both Darwin and NixOS have a `_common/default.nix` that every machine imports. Darwin's `_common` sets:
- `nixpkgs.config.allowUnfree`
- `nixpkgs.overlays` (e.g. pinning `nodejs` to v22)
- `nix.settings.trusted-users`

Each machine's `configuration.nix` then imports `_common` and adds its own specifics on top. The underscore prefix is a naming convention to signal "this is shared infrastructure, not a machine."

### The `dots/` Directory — Dotfile Management

This is the part you're most interested in. Wolfgang's dotfiles live in `modules/dots/` with one subdirectory per program:

```
modules/dots/
├── zsh/
│   └── default.nix    ← home-manager programs.zsh config
├── nvim/
│   └── default.nix    ← programs.nixvim config (via nixvim flake)
├── tmux/
│   └── default.nix    ← programs.tmux config
├── ghostty/
│   └── default.nix    ← programs.ghostty config (or xdg.configFile)
└── neofetch/
    └── default.nix    ← home.file or xdg.configFile
```

Each file is a standalone home-manager module. It sets `programs.<name>.enable = true` and all relevant options. For programs that home-manager has built-in support for (zsh, tmux, git, starship, fzf, etc.), you use the `programs.*` options directly. For programs without native home-manager support (like Ghostty), you use:

```nix
xdg.configFile."ghostty/config".text = ''
  font-family = 0xProto Nerd Font
  font-size = 14
  theme = dark:catppuccin-mocha,light:catppuccin-latte
'';
```

Or point at a source file:
```nix
xdg.configFile."ghostty/config".source = ./config;
```

These dots modules are then imported into the user's `dots.nix` (or directly in the `homeManagerCfg` module list). The result: every program's config is reproducible, version-controlled, and activated on `darwin-rebuild switch`.

### The `users/` Directory

Wolfgang has `modules/users/notthebee/` with:
- `default.nix` — defines the system user (uid, shell, groups)
- `dots.nix` — home-manager base: imports all `../../dots/*`, sets `home.username`, `home.stateVersion`, enables `programs.home-manager`
- `gitconfig.nix` — git settings, including conditional includes from agenix-managed secrets
- `age.nix` — paths to age identity keys for this user

This separates "who is this user" (system-level) from "how is this user's home configured" (home-manager level).

### Secrets with agenix

Wolfgang uses `agenix` to encrypt secrets (API keys, passwords, tokens) with SSH public keys. Encrypted `.age` files live in a private git repo imported as a flake input called `secrets`. At deploy time, `agenix` decrypts them to `/run/agenix/` using the host's SSH key as the identity. Home-manager modules then reference `config.age.secrets.<name>.path` to find them at runtime.

You don't need this immediately — it's an advanced pattern for when you have secrets to protect.

---

## Part 2: Restructuring Plan for Your Config

### Target Directory Structure

```
/etc/nix-darwin/
├── flake.nix                    (slimmed down, delegates to modules/)
├── flake.lock
├── modules/
│   ├── darwin/
│   │   ├── default.nix          (darwinSystem definition, home-manager wiring)
│   │   ├── _common/
│   │   │   └── default.nix      (nixpkgs settings, shared nix settings)
│   │   └── rny-macbook/
│   │       ├── configuration.nix  (Homebrew, system defaults, system packages)
│   │       └── system.nix         (macOS-specific defaults: dock, finder, keyboard)
│   ├── home/
│   │   └── galac/
│   │       ├── default.nix      (home.username, stateVersion, imports all dots)
│   │       ├── git.nix          (programs.git config)
│   │       └── vscode.nix       (programs.vscode config)
│   └── dots/
│       ├── zsh/
│       │   └── default.nix      (programs.zsh: aliases, plugins, shellInit)
│       ├── starship/
│       │   └── default.nix      (programs.starship config)
│       ├── ghostty/
│       │   └── default.nix      (xdg.configFile."ghostty/config")
│       ├── neovim/
│       │   └── default.nix      (programs.neovim or xdg.configFile."nvim/")
│       └── tmux/
│           └── default.nix      (programs.tmux config)
```

### Step-by-Step Implementation

#### Step 1: Restructure flake.nix

The flake simply delegates machine config to `./modules/darwin`:

```nix
outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager, darwin-login-items }:
{
  darwinConfigurations."rny-macbook" = import ./modules/darwin {
    inherit inputs nixpkgs nix-darwin home-manager darwin-login-items;
  };
};
```

Or keep the current flake structure and just change `./configuration.nix` to import from `./modules/darwin/rny-macbook/configuration.nix`. Either works.

#### Step 2: Create `modules/darwin/_common/default.nix`

Pull out shared nix/nixpkgs settings that will apply to any future machine:

```nix
{ pkgs, ... }: {
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  environment.systemPackages = with pkgs; [ git curl wget ];
  programs.zsh.enable = true;
}
```

#### Step 3: Create `modules/darwin/rny-macbook/configuration.nix`

Move machine-specific content here — Homebrew casks, fonts, login items, `system.stateVersion`. This file's only job is "what makes rny-macbook different from any other Mac."

#### Step 4: Create `modules/darwin/rny-macbook/system.nix`

Extract all `system.defaults.*` blocks into this file. This is purely macOS preference settings (dock, finder, keyboard, trackpad). Keeping it separate makes it easy to find and tweak.

#### Step 5: Create `modules/dots/zsh/default.nix`

Move all zsh config from `home.nix` into its own module:

```nix
{ pkgs, ... }: {
  programs.zsh = {
    enable = true;
    enableAutosuggestions = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      ls  = "eza --icons";
      ll  = "eza -l --icons --git";
      la  = "eza -la --icons --git";
      cat = "bat";
      grep = "rg";
      rebuild = "sudo darwin-rebuild switch --flake /etc/nix-darwin#rny-macbook";
    };
    initExtra = ''
      # any raw zsh that doesn't fit options
    '';
  };
  programs.fzf.enable = true;
}
```

#### Step 6: Create `modules/dots/ghostty/default.nix`

Ghostty has no native home-manager module yet, so use `xdg.configFile`:

```nix
{ ... }: {
  xdg.configFile."ghostty/config".text = ''
    font-family = 0xProto Nerd Font
    font-size = 14
    theme = dark:catppuccin-mocha,light:catppuccin-latte
    background-opacity = 0.95
    shell-integration = zsh
  '';
}
```

If you prefer to keep the Ghostty config editable as a plain file, use `.source` pointing at a file in the repo:
```nix
xdg.configFile."ghostty/config".source = ./config;
```

#### Step 7: Create `modules/dots/neovim/default.nix`

For Neovim you have two options:

**Option A — Manage the whole config in Nix (Wolfgang's approach with nixvim):**
Use the `nixvim` flake input. This lets you declare plugins, LSP servers, keymaps in Nix. It's powerful but requires learning nixvim's option set.

**Option B — Copy your existing config into the Nix store:**
```nix
{ ... }: {
  xdg.configFile."nvim".source = ./nvim;  # ./nvim/ is a directory in your repo
  # or: xdg.configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink "/etc/nix-darwin/nvim";
}
```
Option B lets you keep editing `nvim/` as normal files, but they're tracked in your nix-darwin repo.

**Recommendation:** Start with Option B (lower friction). Add nixvim later when you want full declarative plugin management.

#### Step 8: Create `modules/dots/tmux/default.nix`

home-manager has native tmux support:

```nix
{ ... }: {
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    historyLimit = 10000;
    keyMode = "vi";
    extraConfig = ''
      # any options not covered by home-manager options
    '';
  };
}
```

#### Step 9: Create `modules/home/galac/default.nix`

This replaces `home.nix` as the home-manager entrypoint for your user:

```nix
{ pkgs, ... }: {
  home.username = "galac";
  home.homeDirectory = "/Users/galac";
  home.stateVersion = "25.11";
  programs.home-manager.enable = true;

  imports = [
    ../../dots/zsh
    ../../dots/ghostty
    ../../dots/neovim
    ../../dots/tmux
    ../../dots/starship
    ./git.nix
    ./vscode.nix
  ];

  home.packages = with pkgs; [
    ripgrep fd bat eza fzf htop tree
    rustup faust
  ];
}
```

#### Step 10: Wire it all together in flake.nix

```nix
home-manager.users.galac = import ./modules/home/galac;
```

And in `configuration.nix` (or a new `modules/darwin/default.nix`):
```nix
imports = [
  ./_common
  ./rny-macbook/configuration.nix
  ./rny-macbook/system.nix
];
```

---

## Migration Order (Safest Path)

Do these one at a time, rebuilding and verifying between each:

1. Extract `system.defaults` into `system.nix` (pure refactor, zero risk)
2. Extract zsh config into `modules/dots/zsh/default.nix`
3. Extract starship into `modules/dots/starship/default.nix`
4. Extract git config into `modules/home/galac/git.nix`
5. Extract VSCode config into `modules/home/galac/vscode.nix`
6. Add Ghostty to `modules/dots/ghostty/default.nix`
7. Add Neovim (start with `.source` method, Option B above)
8. Add Tmux to `modules/dots/tmux/default.nix`
9. Create `_common/default.nix` and move shared nix settings
10. Create `modules/home/galac/default.nix` to replace `home.nix`

---

## Verification

After each step:
```bash
sudo darwin-rebuild switch --flake /etc/nix-darwin#rny-macbook
```

Check that:
- Shell (zsh) works: aliases respond, plugins active, starship prompt shows
- Ghostty config is applied (font, theme visible)
- Neovim opens and plugins load
- `git config --list` shows your name/email
- VSCode has correct font and extensions

For dotfiles specifically, verify with:
```bash
cat ~/.config/ghostty/config   # should show what you declared in Nix
ls ~/.config/nvim/             # should show your neovim config
```

---

## What You're NOT Doing (Yet)

- **agenix secrets**: Not needed until you have secrets to protect
- **flake-parts**: Optional complexity, skip for now
- **Machine auto-discovery**: Only useful when you have multiple Macs
- **nixvim**: Optional, only if you want fully-declarative Neovim
- **Multiple users**: Stay single-user for now

The goal is to match Wolfgang's *organization principles* (one concern per file, dots managed by home-manager) without adopting his full complexity (homelab services, multi-host, secrets infra).
