# Neovim Setup (VSCode Migration)

`neovim` is installed as a bare binary via `home.packages`. Config lives at `~/.config/nvim/` and is **not** Nix-managed — edit it freely without a rebuild.

## Config structure

```
~/.config/nvim/
├── init.lua              # entry point
└── lua/
    ├── options.lua       # vim options
    ├── keymaps.lua       # keybindings
    └── plugins/          # one file per plugin (lazy.nvim convention)
```

## 1. Plugin manager: lazy.nvim

Bootstrap in `init.lua`:

```lua
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git", lazypath })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("lua/plugins")  -- auto-loads lua/plugins/*.lua
```

Run `:Lazy` to open the UI, `U` to update all plugins.

## 2. VSCode feature → Neovim equivalent

| VSCode | Neovim plugin | Notes |
|--------|--------------|-------|
| Explorer sidebar | **neo-tree.nvim** | `<leader>e` to toggle |
| Quick Open (Ctrl+P) | **telescope.nvim** | `<leader>ff` find files, `<leader>fg` live grep |
| IntelliSense | **nvim-lspconfig** + **mason.nvim** | Mason installs LSP servers with `:MasonInstall` |
| Autocomplete | **nvim-cmp** | Tab/Enter to confirm, Ctrl+Space to trigger |
| Syntax highlighting | **nvim-treesitter** | Much better than regex-based; `:TSInstall <lang>` |
| Git gutter | **gitsigns.nvim** | Inline blame, hunk preview, stage hunks |
| Terminal | `:term` or **toggleterm.nvim** | `<C-\><C-n>` to exit insert mode in terminal |
| Format on save | **conform.nvim** | Per-filetype formatters |
| Problems panel | **trouble.nvim** | `<leader>xx` to open diagnostics list |
| Command palette | **which-key.nvim** | Shows available keybinds after prefix delay |
| Multiple cursors | **vim-visual-multi** | `<C-n>` to select next occurrence |

## 3. Core plugin files

### `lua/plugins/ui.lua`
```lua
return {
  -- Theme (matches Ghostty catppuccin-mocha)
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    config = function()
      vim.cmd.colorscheme("catppuccin-mocha")
    end,
  },
  -- Status line
  { "nvim-lualine/lualine.nvim", opts = { theme = "catppuccin" } },
  -- File explorer
  {
    "nvim-neo-tree/neo-tree.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "nvim-tree/nvim-web-devicons", "MunifTanjim/nui.nvim" },
    keys = { { "<leader>e", "<cmd>Neotree toggle<cr>" } },
  },
}
```

### `lua/plugins/telescope.lua`
```lua
return {
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>" },
      { "<leader>fr", "<cmd>Telescope oldfiles<cr>" },
    },
  },
}
```

### `lua/plugins/lsp.lua`
```lua
return {
  -- Server installer UI
  { "williamboman/mason.nvim", config = true },
  { "williamboman/mason-lspconfig.nvim" },
  {
    "neovim/nvim-lspconfig",
    config = function()
      local lspconfig = require("lspconfig")

      -- Nix: install with :MasonInstall nil
      lspconfig.nil_ls.setup({})

      -- Rust: handled by rustaceanvim below (don't set up rust_analyzer here)
    end,
  },
  -- Rust (full feature set: expand macros, runnables, debugger hooks)
  {
    "mrcjkb/rustaceanvim",
    version = "^4",
    ft = "rust",
  },
}
```

### `lua/plugins/completion.lua`
```lua
return {
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
    },
    config = function()
      local cmp = require("cmp")
      cmp.setup({
        snippet = { expand = function(args) require("luasnip").lsp_expand(args.body) end },
        mapping = cmp.mapping.preset.insert({
          ["<Tab>"]   = cmp.mapping.select_next_item(),
          ["<S-Tab>"] = cmp.mapping.select_prev_item(),
          ["<CR>"]    = cmp.mapping.confirm({ select = true }),
          ["<C-Space>"] = cmp.mapping.complete(),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "buffer" },
          { name = "path" },
        }),
      })
    end,
  },
}
```

### `lua/plugins/treesitter.lua`
```lua
return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = { "lua", "nix", "rust", "toml", "bash", "markdown" },
        highlight = { enable = true },
        indent = { enable = true },
      })
    end,
  },
}
```

## 4. Recommended `options.lua`

```lua
local o = vim.opt
o.number         = true
o.relativenumber = true     -- relative line numbers (essential for vim motions)
o.signcolumn     = "yes"    -- always show gutter (prevents layout jumps)
o.tabstop        = 4
o.shiftwidth     = 4
o.expandtab      = true
o.scrolloff      = 8
o.termguicolors  = true
o.undofile       = true     -- persistent undo across sessions
o.splitright     = true
o.splitbelow     = true
o.updatetime     = 250      -- faster CursorHold (used by LSP hover)
```

## 5. Language-specific notes

### Nix
- LSP: `nil` (`:MasonInstall nil`) or `nixd` (faster, install via `pkgs.nixd` in `home.packages`)
- Formatter: `nixpkgs-fmt` or `alejandra` — add to `home.packages`, then configure conform.nvim

### Rust
- `rustaceanvim` uses the `rust-analyzer` from your active `rustup` toolchain automatically
- `:RustLsp runnables` to run targets, `:RustLsp expandMacro` to inspect macros

## 6. Learning resources

- `:Tutor` — built-in interactive tutorial (30 min, do this first)
- `:help <topic>` — comprehensive offline docs
- `kickstart.nvim` (github.com/nvim-lua/kickstart.nvim) — well-commented single-file starter config, good to read even if you don't use it
