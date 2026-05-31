# Starship Customization

Starship is managed by home-manager. All config goes in `home.nix` under `programs.starship.settings` — do **not** edit `~/.config/starship.toml` directly, it will be overwritten on rebuild.

## Quick start: apply a preset

The fastest way to get a good-looking prompt is to start from a preset. Preview them at https://starship.rs/presets/

The `nerd-font-symbols` preset works well with 0xProto Nerd Font already installed:

```nix
programs.starship = {
  enable = true;
  enableZshIntegration = true;
  settings = {
    add_newline = true;

    character = {
      success_symbol = "[➜](bold green)";
      error_symbol = "[➜](bold red)";
    };

    git_branch = {
      symbol = " ";
    };

    nix_shell = {
      symbol = " ";
      format = "via [$symbol$state]($style) ";
    };

    rust = {
      symbol = " ";
    };

    directory = {
      truncation_length = 3;
      truncate_to_repo = true;
    };
  };
};
```

## Useful modules for this setup

| Module | What it shows | Enable by default? |
|--------|--------------|-------------------|
| `git_branch` | current branch + status | yes |
| `nix_shell` | active nix-shell / flake | yes (auto-detected) |
| `rust` | active toolchain version | yes (when in Rust project) |
| `directory` | cwd with smart truncation | yes |
| `cmd_duration` | time for long commands | yes (>2s) |
| `time` | clock | no — add `time.disabled = false` |

## Disable a module

```nix
settings = {
  package.disabled = true;    # hides version from package.json etc.
  nodejs.disabled = true;
};
```

## Minimal one-liner prompt (if you want less noise)

```nix
settings = {
  format = "$directory$git_branch$git_status$nix_shell$character";
  add_newline = false;
};
```

## Applying changes

```bash
rebuild   # sudo darwin-rebuild switch --flake /etc/nix-darwin#rny-macbook
```

Then open a new shell (or `exec zsh`) — changes take effect immediately in new sessions.
