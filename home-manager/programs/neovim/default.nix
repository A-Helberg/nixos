{ pkgs, config, lib, ... }:
let

  treesitterWithGrammars = (pkgs.vimPlugins.nvim-treesitter.withPlugins (p: [
    p.bash
    p.clojure
    p.comment
    p.css
    p.dockerfile
    p.fish
    p.gitattributes
    p.gitignore
    p.go
    p.gomod
    p.gowork
    p.hcl
    p.javascript
    p.jq
    p.json5
    p.json
    p.lua
    p.make
    p.markdown
    p.nix
    p.python
    p.rust
    p.toml
    p.typescript
    p.vue
    p.yaml
  ]));

  treesitter-parsers = pkgs.symlinkJoin {
    name = "treesitter-parsers";
    paths = treesitterWithGrammars.dependencies;
  };

  lazy-nix-ref = "63b20ed071647bb492ed3256fbda709e4bfedc45";
  lazy-nix-sha = "sha256-TBDZGj0NXkWvJZJ5ngEqbhovf6RPm9N+Rmphz92CS3Q" ;

  lazy-nix-helper-nvim = pkgs.vimUtils.buildVimPlugin {
    name = "lazy-nix-helper.nvim";
    src = pkgs.fetchFromGitHub {
      owner = "b-src";
      repo = "lazy-nix-helper.nvim";
      rev = lazy-nix-ref;
      hash = lazy-nix-sha;
    };
  };

  sanitizePluginName = input:
  let
    name = lib.strings.getName input;
    intermediate = lib.strings.removePrefix "vimplugin-" name;
    result = lib.strings.removePrefix "lua5.1-" intermediate;
  in result;

  pluginList = plugins: lib.strings.concatMapStrings (plugin: "  [\"${sanitizePluginName plugin.name}\"] = \"${plugin.outPath}\",\n") plugins;
in
{
  home.packages = with pkgs; [
    ripgrep
    fzf
    fd
    lua-language-server
    rust-analyzer-unwrapped
    black
    stylua
    # needed to install lsp's
    unzip

    # LSs
    luajitPackages.lua-lsp
  ];

  programs.neovim = {
    enable = true;
    package = pkgs.neovim-unwrapped;
    vimAlias = true;
    coc.enable = false;
    withNodeJs = true;

    plugins = [
      treesitterWithGrammars
    ];

  };

  xdg.configFile."nvim/lua/nixos.lua" = {
    text = ''
      local plugins = {
      ${pluginList config.programs.neovim.plugins}
      }
      local lazy_nix_helper_path = "${lazy-nix-helper-nvim}"
      if not vim.loop.fs_stat(lazy_nix_helper_path) then
        lazy_nix_helper_path = vim.fn.stdpath("data") .. "/lazy_nix_helper/lazy_nix_helper.nvim"
        if not vim.loop.fs_stat(lazy_nix_helper_path) then
          vim.fn.system({
            "git",
            "clone",
            "--filter=blob:none",
            "https://github.com/b-src/lazy_nix_helper.nvim.git",
            lazy_nix_helper_path,
          })
        end
      end

      -- add the Lazy Nix Helper plugin to the vim runtime
      vim.opt.rtp:prepend(lazy_nix_helper_path)

      -- call the Lazy Nix Helper setup function
      local non_nix_lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
      local lazy_nix_helper_opts = { lazypath = non_nix_lazypath, input_plugin_table = plugins }
      require("lazy-nix-helper").setup(lazy_nix_helper_opts)

      -- get the lazypath from Lazy Nix Helper
      local lazypath = require("lazy-nix-helper").lazypath()
      if not vim.loop.fs_stat(lazypath) then
        vim.fn.system({
          "git",
          "clone",
          "--filter=blob:none",
          "https://github.com/folke/lazy.nvim.git",
          "--branch=stable", -- latest stable release
          lazypath,
        })
      end
      vim.opt.rtp:prepend(lazypath)
    '';
    };

  xdg.configFile."nvim/init.lua" = {
    source = ./nvim/init.lua;
    recursive = true;
  };

#  home.file."./.config/nvim/lua/kidsan/init.lua".text = ''
#    require("kidsan.set")
#    require("kidsan.remap")
#    vim.opt.runtimepath:append("${treesitter-parsers}")
#  '';

  # Treesitter is configured as a locally developed module in lazy.nvim
  # we hardcode a symlink here so that we can refer to it in our lazy config
  home.file."./.local/share/nvim/nix/nvim-treesitter/" = {
    recursive = true;
    source = treesitterWithGrammars;
  };

}
