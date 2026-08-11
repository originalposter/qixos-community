{ pkgs }:

# ============================================================
# NIXVIM CONFIG
# Translates your lazy.nvim setup into nixvim's module system.
#
# Key difference from the nvf version:
#   - Almost every plugin you use has a first-class nixvim module.
#   - DAP adapter/configuration setup still needs extraConfigLua
#     because it's inherently closure-heavy Lua (pidof callbacks,
#     pythonPath functions, etc.). That's fine and expected.
#   - lib.nixvim.mkRaw wraps raw Lua where nixvim needs a Lua
#     value inside a Nix attrset (e.g. on_attach functions).
# ============================================================

let
  # mkRaw shim for standalone makeNixvim usage.
  # When used as a HM/NixOS module, this comes from lib automatically.
  # In standalone mode we just pass it through pkgs or inline it.
  mkRaw = expr: { __raw = expr; };
in
{
  # ---- GLOBALS -------------------------------------------------
  globals = {
    mapleader = ",";
    maplocalleader = " ";
    # Disable netrw (required by nvim-tree)
    loaded_netrw = 1;
    loaded_netrwPlugin = 1;
  };

  # ---- OPTIONS -------------------------------------------------
  opts = {
    termguicolors = true;
    relativenumber = true;
    number = true;
    updatetime = 300;
    ignorecase = true;
    smartcase = true;
    signcolumn = "yes";
  };

  # ---- COLORSCHEME ---------------------------------------------
  # nixvim has first-class gruvbox support - one line.
  colorschemes.gruvbox = {
    enable = true;
    settings.contrast_dark = "hard"; # or "medium" / "soft"
  };

  # ---- PLUGINS -------------------------------------------------
  plugins = {

    # ---- FILE TREE ---------------------------------------------
    nvim-tree = {
      enable = true;
      settings = {
        sort.sorter = "case_sensitive";
        view.width = 30;
        renderer.group_empty = true;
        # on_attach is a Lua function - use mkRaw
        on_attach = mkRaw ''
          function(bufnr)
            local api = require("nvim-tree.api")

            local function opts(desc)
              return {
                desc = "nvim-tree: " .. desc,
                buffer = bufnr,
                noremap = true,
                silent = true,
                nowait = true,
              }
            end

            api.config.mappings.default_on_attach(bufnr)

            vim.keymap.set('n', '<C-t>', api.tree.close, opts('Close'))
            vim.keymap.set('n', '?', api.tree.toggle_help, opts('Help'))
            vim.keymap.set('n', 'U', api.tree.change_root_to_parent, opts('Change root to parent'))
            vim.keymap.set('n', 'CD', api.tree.change_root_to_node, opts('Change root to node'))

            vim.keymap.set('n', 'cd', function()
              local node = api.tree.get_node_under_cursor()
              if node and node.type == "directory" then
                vim.cmd("cd " .. vim.fn.fnameescape(node.absolute_path))
                print("cwd -> " .. node.absolute_path)
              else
                print("not a directory")
              end
            end, opts("Set cwd to directory under cursor"))

            vim.keymap.set('n', 'O', function()
              local node = api.tree.get_node_under_cursor()
              if node and node.type == "directory" then
                api.tree.close()
                vim.cmd("edit " .. node.absolute_path)
              end
            end, opts("Open dir in oil"))
          end
        '';
      };
    };

    # ---- OIL ---------------------------------------------------
    oil = {
      enable = true;
    };

    # ---- FLASH -------------------------------------------------
    flash = {
      enable = true;
      settings = {
        modes.char.enabled = false;
        label = {
          style = "inline";
          rainbow.enabled = true;
          highlight = {
            label = "FlashLabel";
            current = "FlashKey";
          };
        };
      };
    };

    # ---- FZF-LUA -----------------------------------------------
    fzf-lua = {
      enable = true;
    };

    # ---- TOGGLETERM --------------------------------------------
    toggleterm = {
      enable = true;
      settings = {
        open_mapping = "[[<C-k>]]";
        direction = "horizontal";
        size = 10;
        start_in_insert = true;
        insert_mappings = true;
        shade_terminals = true;
        persist_size = true;
      };
    };

    # ---- FUGITIVE ----------------------------------------------
    fugitive.enable = true;

    # ---- TREESITTER --------------------------------------------
    treesitter = {
      enable = true;
      settings = {
        highlight.enable = true;
        indent.enable = true;
      };
      grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        lua python rust javascript typescript c go svelte html css
      ];
    };

    # ---- AERIAL ------------------------------------------------
    aerial = {
      enable = true;
    };

    # ---- LSP ---------------------------------------------------
    # nixvim's lsp module auto-installs the server binary from nixpkgs
    # and wires up lspconfig. Each server supports extraOptions for
    # raw lspconfig overrides (e.g. rootDir).
    lsp = {
      enable = true;
      servers = {
        pyright.enable = true;

        ts_ls.enable = true;

        rust_analyzer = {
          enable = true;
          # nixvim can install rustc/cargo for you, but since you're
          # likely using a Rust toolchain from your shell/devshell,
          # disable auto-install to avoid conflicts:
          installRustc = false;
          installCargo = false;
        };

        svelte = {
          enable = true;
          rootMarkers = [ "svelte.config.js" "svelte.config.cjs" "package.json" ".git" ];

        };

        nixd.enable = true;
        bashls.enable = true;
      };
    };

    # ---- CMP ---------------------------------------------------
    cmp = {
      enable = true;
      settings = {
        preselect = mkRaw "require('cmp').PreselectMode.Item";
        completion.completeopt = "menu,menuone,noinsert";

        mapping = {
          "<CR>" = mkRaw "require('cmp').mapping.confirm({ select = true })";
          "<C-Space>" = mkRaw "require('cmp').mapping.complete()";
          "<Tab>" = mkRaw ''
            require('cmp').mapping(function(fallback)
              if require('cmp').visible() then
                require('cmp').select_next_item()
              else
                fallback()
              end
            end, { "i", "s" })
          '';
          "<S-Tab>" = mkRaw ''
            require('cmp').mapping(function(fallback)
              if require('cmp').visible() then
                require('cmp').select_prev_item()
              else
                fallback()
              end
            end, { "i", "s" })
          '';
        };

        sources = [
          { name = "nvim_lsp"; }
        ];
      };
    };

    # cmp source for LSP
    cmp-nvim-lsp.enable = true;

    # ---- DAP ---------------------------------------------------
    dap = {
      enable = true;

      # Adapter + configuration setup lives in extraConfigLua below
      # because it's too closure-heavy to express in Nix attrs.
      # (pidof callbacks, pythonPath functions, etc.)
    };

    dap-ui.enable = true;

    # ---- MINI ICONS (oil dependency) ---------------------------
    mini = {
      enable = true;
      modules.icons = {};
    };

    # ---- WEB DEVICONS (nvim-tree dependency) -------------------
    web-devicons.enable = true;

  }; # end plugins

  # ---- EXTRA PACKAGES IN PATH ----------------------------------
  # These get added to nvim's runtime PATH.
  # codelldb is inside the lldb package on nixpkgs.
  extraPackages = with pkgs; [
    lldb
  ];

  # ---- KEYMAPS -------------------------------------------------
  # nixvim has a first-class keymaps list.
  # Anything needing Lua closures (jump stack, flash actions)
  # goes in extraConfigLua below.

  keymaps = [
    # nvim-tree
    { mode = "n"; key = "<C-t>"; action = ":NvimTreeToggle<CR>"; options.noremap = true; }

    # fzf-lua
    { mode = "n"; key = "J"; action = ":FzfLua files<CR>";     options.noremap = true; }
    { mode = "n"; key = "K"; action = ":FzfLua buffers<CR>";   options.noremap = true; }
    { mode = "n"; key = "H"; action = ":FzfLua live_grep<CR>"; options.noremap = true; }

    # LSP (non-closure ones)
    { mode = "n"; key = "L";   action = mkRaw "vim.lsp.buf.hover";       options.desc = "LSP hover docs"; }
    { mode = "n"; key = ";n";  action = mkRaw "vim.lsp.buf.rename";      options.desc = "LSP rename"; }
    { mode = "n"; key = ";a";  action = mkRaw "vim.lsp.buf.code_action"; options.desc = "LSP code action"; }
    { mode = "n"; key = ";f";  action = mkRaw "vim.lsp.buf.format";      options.desc = "LSP format"; }

    # Aerial
    { mode = "n"; key = "<A-t>"; action = ":AerialToggle<CR>"; options.noremap = true; }

    # Fugitive
    { mode = "n"; key = "<leader>g";  action = ":G<CR>";          options.desc = "Git status (fugitive)"; }
    { mode = "n"; key = "<leader>gd"; action = ":Gdiffsplit<CR>"; options.desc = "Git diff split"; }
    { mode = "n"; key = "<leader>gb"; action = ":Git blame<CR>";  options.desc = "Git blame"; }

    # General
    { mode = "n";        key = "co";           action = "zf%";          options.noremap = true; }
    { mode = ["i" "c"];  key = "<C-v>";        action = "<C-r>+";       options.noremap = true; }
    { mode = "v";        key = "<C-c>";        action = ''"+y'';        options.noremap = true; }
    { mode = "v";        key = "<C-x>";        action = ''"+d'';        options.noremap = true; }
    { mode = "n";        key = "<C-a>";        action = "ggVG$";        options.noremap = true; }
    { mode = "i";        key = "jk";           action = "<Esc>";        options.noremap = true; }
    { mode = "i";        key = "Jk";           action = "<Esc>";        options.noremap = true; }
    { mode = "n";        key = "T";            action = ":write<CR>";   options.noremap = true; }
    { mode = "n";        key = "<C-s>";        action = ":write<CR>";   options.noremap = true; }
    { mode = "n";        key = "gq";           action = ":q<CR>";       options.noremap = true; }
    { mode = "n";        key = "<A-j>";        action = ":m .+1<CR>=="; options.noremap = true; }
    { mode = "n";        key = "<A-k>";        action = ":m .-2<CR>=="; options.noremap = true; }
    { mode = "v";        key = "<A-j>";        action = ":m .+1<CR>=="; options.noremap = true; }
    { mode = "v";        key = "<A-k>";        action = ":m .-2<CR>=="; options.noremap = true; }
    { mode = "i";        key = "<C-h>";        action = "<backspace>";  options.noremap = true; }
    { mode = "i";        key = "<C-l>";        action = "<delete>";     options.noremap = true; }
    { mode = "n";        key = "<CR>";         action = "o<Esc>";       options.noremap = true; }
    { mode = "n";        key = "<leader><leader>"; action = ":b#<CR>";  options.noremap = true; }
  ];

  # ---- AUTOCOMMANDS --------------------------------------------
  autoCmd = [
    # Hover diagnostics (show once per cursor position, not repeatedly)
    # Can't express the stateful last_pos logic here - goes in extraConfigLua.

    # Lua filetype indent
    {
      event = "FileType";
      pattern = "lua";
      callback = mkRaw ''
        function()
          vim.bo.expandtab   = true
          vim.bo.shiftwidth  = 4
          vim.bo.tabstop     = 4
          vim.bo.softtabstop = 4
        end
      '';
    }

    # CD to LSP root on attach
    {
      event = "LspAttach";
      callback = mkRaw ''
        function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          local root_dir = client and client.config and client.config.root_dir
          if root_dir then
            vim.cmd("cd " .. vim.fn.fnameescape(root_dir))
            print("cwd set to LSP root: " .. root_dir)
          end
        end
      '';
    }

    # Enter to jump in quickfix
    {
      event = "FileType";
      pattern = "qf";
      callback = mkRaw ''
        function()
          vim.keymap.set("n", "<CR>", "<Cmd>.cc<CR>", { buffer = true })
        end
      '';
    }

    {
      event = "FileType";
      pattern = "nix";
      callback = mkRaw ''
        function()
          vim.bo.expandtab   = true
          vim.bo.shiftwidth  = 2
          vim.bo.tabstop     = 2
          vim.bo.softtabstop = 2
          vim.opt_local.indentkeys:remove("0#")
        end
      '';
    }
  ];

  # ---- EXTRA LUA -----------------------------------------------
  # Stuff that genuinely needs Lua closures and can't be expressed
  # as Nix attrs: jump stack, flash keymaps, DAP full config,
  # the stateful CursorHold diagnostic handler, and toggle keymaps.

  extraConfigLua = ''
    -- Make git root cwd
    vim.api.nvim_create_autocmd("BufEnter", {
      callback = function()
        local git_root = vim.fs.find(".git", { upward = true, path = vim.fn.expand("%:p:h") })[1]
        if git_root then
          vim.cmd("cd " .. vim.fn.fnameescape(vim.fs.dirname(git_root)))
        end
      end,
    })
    -- ============================================================
    -- CURSOR HOLD DIAGNOSTICS
    -- Show hover diagnostic once per position, not on every tick.
    -- ============================================================
    local _last_diag_pos = nil
    vim.api.nvim_create_autocmd("CursorHold", {
      callback = function()
        local pos = vim.api.nvim_win_get_cursor(0)
        local key = vim.api.nvim_buf_get_name(0) .. ":" .. pos[1] .. ":" .. pos[2]
        if key ~= _last_diag_pos then
          vim.diagnostic.open_float(nil, { scope = "cursor", focusable = false })
          _last_diag_pos = key
        end
      end,
    })

    -- ============================================================
    -- JUMP STACK
    -- ============================================================
    local jumpstack = {}

    local function mark_jump()
      local pos = vim.api.nvim_win_get_cursor(0)
      local buf = vim.api.nvim_get_current_buf()
      table.insert(jumpstack, { buf = buf, pos = pos })
    end

    local function jump_back()
      local last = table.remove(jumpstack)
      if last then
        vim.api.nvim_set_current_buf(last.buf)
        vim.api.nvim_win_set_cursor(0, last.pos)
      else
        vim.notify("Jump stack empty", vim.log.levels.WARN)
      end
    end

    -- LSP keymaps that need closures
    vim.keymap.set("n", "<leader>j", function()
      mark_jump()
      vim.lsp.buf.definition()
    end, { desc = "LSP: Go to definition with stack" })

    vim.keymap.set("n", "<leader>b", jump_back, { desc = "Jump back" })

    vim.keymap.set("n", ";r", function()
      mark_jump()
      require('fzf-lua').lsp_references()
    end, { desc = "LSP references" })

    -- Toggle relative number
    vim.keymap.set("n", "<leader>m", function()
      vim.wo.relativenumber = not vim.wo.relativenumber
    end, { noremap = true })

    -- ============================================================
    -- FLASH KEYMAPS
    -- (flash.nvim keys with mode arrays need extraConfigLua)
    -- ============================================================
    vim.keymap.set({ "n", "x", "o" }, "<C-f><C-f>",
      function() require("flash").jump() end,
      { desc = "Flash" })

    vim.keymap.set({ "n", "x", "o" }, "<C-f>f",
      function() require("flash").jump() end,
      { desc = "Flash" })

    vim.keymap.set({ "n", "x", "o" }, "<C-f><C-s>",
      function() require("flash").treesitter() end,
      { desc = "Flash Treesitter" })

    vim.keymap.set("o", "<C-f><C-r>",
      function() require("flash").remote() end,
      { desc = "Remote Flash" })

    vim.keymap.set({ "o", "x" }, "<C-f><C-t>",
      function() require("flash").treesitter_search() end,
      { desc = "Treesitter Search" })

    -- ============================================================
    -- DAP - FULL CONFIG
    -- Too closure-heavy to express cleanly in Nix attrs.
    -- ============================================================
    local dap = require('dap')

    -- Keymaps
    vim.keymap.set("n", ";q", function() dap.toggle_breakpoint() end, { desc = "toggle breakpoint" })
    vim.keymap.set("n", ";w", function() dap.continue() end,          { desc = "debug continue" })
    vim.keymap.set("n", ";e", function() dap.step_over() end,         { desc = "debug step over" })
    vim.keymap.set("n", ";d", function() dap.step_into() end,         { desc = "debug step into" })
    vim.keymap.set("n", ";c", function() dap.step_out() end,          { desc = "debug step out" })
    vim.keymap.set("n", ";s", function() dap.run_to_cursor() end,     { desc = "debug run to cursor" })
    vim.keymap.set("n", ";i", function() require('dap.ui.widgets').hover() end, { desc = "debug inspect value" })
    vim.keymap.set("n", ";ss",function() dap.close() end,             { desc = "stop debugging" })

    -- codelldb adapter (codelldb is on PATH via extraPackages = [pkgs.lldb])
    dap.adapters.codelldb = {
      type = 'executable',
      command = "codelldb",
    }

    local function get_default_rust_program_path()
      local workspace = vim.fn.getcwd()
      local program_name = vim.fn.fnamemodify(workspace, ":t")
      return workspace .. '/target/debug/' .. program_name
    end

    dap.configurations.cpp = {
      {
        name = "Attach to name",
        type = "codelldb",
        request = "attach",
        pid = function()
          local name = vim.fn.input('Enter pidof name: ')
          local handle = io.popen("pidof " .. name)
          local pid = handle:read("*a")
          handle:close()
          return pid:match("^%s*(.-)%s*$")
        end,
        stopOnEntry = true,
      },
      {
        name = "Attach to PID",
        type = "codelldb",
        request = "attach",
        pid = function()
          return tonumber(vim.fn.input('Enter PID: '))
        end,
        stopOnEntry = true,
      },
      {
        name = "Manually launch file",
        type = "codelldb",
        request = "launch",
        program = function()
          return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
        end,
        cwd = "''${workspaceFolder}",
        stopOnEntry = true,
      },
      {
        name = "Remote attach to name",
        type = "codelldb",
        request = "attach",
        pid = function()
          local name = vim.fn.input('Enter pidof name: ')
          local handle = io.popen("pidof " .. name)
          local pid = handle:read("*a")
          handle:close()
          return pid:match("^%s*(.-)%s*$")
        end,
        initCommands = {
          "platform select remote-linux",
          "platform connect connect://127.0.0.1:1234",
          "settings set target.inherit-env false",
        },
      },
      {
        name = "Remote launch",
        type = "codelldb",
        request = "launch",
        program = function()
          return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
        end,
        initCommands = {
          "platform select remote-linux",
          "platform connect connect://127.0.0.1:1234",
          "settings set target.inherit-env false",
        },
      },
    }

    dap.configurations.c    = dap.configurations.cpp
    dap.configurations.rust = dap.configurations.cpp

    table.insert(dap.configurations.rust, 1, {
      name    = "Launch Default Rust Program",
      type    = "codelldb",
      request = "launch",
      program = get_default_rust_program_path,
      cwd     = "''${workspaceFolder}",
      stopOnEntry = true,
    })

    -- Python adapter
    dap.adapters.python = function(cb, config)
      if config.request == 'attach' then
        local port = (config.connect or config).port
        local host = (config.connect or config).host or '127.0.0.1'
        cb({
          type = 'server',
          port = assert(port, '`connect.port` is required for a python attach config'),
          host = host,
          options = { source_filetype = 'python' },
        })
      else
        local home = os.getenv("HOME")
        cb({
          type    = 'executable',
          command = home .. '/.virtualenvs/debugpy/bin/python',
          args    = { '-m', 'debugpy.adapter' },
          options = { source_filetype = 'python' },
        })
      end
    end

    dap.configurations.python = {
      {
        type    = 'python',
        request = 'launch',
        name    = "Launch file",
        program = "''${file}",
        pythonPath = function()
          local cwd = vim.fn.getcwd()
          if vim.fn.executable(cwd .. '/venv/bin/python') == 1 then
            return cwd .. '/venv/bin/python'
          elseif vim.fn.executable(cwd .. '/.venv/bin/python') == 1 then
            return cwd .. '/.venv/bin/python'
          else
            return '/usr/bin/python'
          end
        end,
      },
    }
  '';
}
