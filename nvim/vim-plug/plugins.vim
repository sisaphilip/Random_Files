" auto-install vim-plug
if empty(glob('~/.config/nvim/autoload/plug.vim'))
  silent !curl -fLo ~/.config/nvim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  "autocmd VimEnter * PlugInstall
  "autocmd VimEnter * PlugInstall | source $MYVIMRC
endif

call plug#begin('~/.config/nvim/autoload/plugged')


    " Better Syntax Support
    Plug 'sheerun/vim-polyglot'
    Plug 'nvim-lualine/lualine.nvim'
    Plug 'jiangmiao/auto-pairs'
   
    Plug 'morhetz/gruvbox'
    Plug 'neovim/nvim-lspconfig'
    Plug 'hrsh7th/nvim-compe'
"    Plug 'neoclide/coc.nvim'
    Plug 'eddyekofo94/gruvbox-flat.nvim'
    Plug 'desmap/ale-sensible' | Plug 'w0rp/ale'
    "Plug 'dense-analysis/ale'
    Plug 'autozimu/LanguageClient-neovim', {
    \ 'branch': 'next',
    \ 'do': 'bash install.sh && npm install -g flow-bin',
    \ }

    Plug 'https://github.com/vim-airline/vim-airline' " Status bar
    
    ">>>>>>>>>RUST
    Plug 'rust-lang/rust.vim'
    Plug 'rust-analyzer/rust-analyzer'
    Plug 'simrat39/rust-tools.nvim'
    ">>>>>>>>>RUST Debugging
    Plug 'nvim-lua/plenary.nvim'
    Plug 'mfussenegger/nvim-dap'

call plug#end()



"themes
colorscheme gruvbox-flat
 
"COLORS
highlight Normal     ctermbg=NONE guibg=NONE
highlight LineNr     ctermbg=NONE guibg=NONE
highlight SignColumn ctermbg=NONE guibg=NONE

let g:ale_fixers = ['prettier', 'standard']

"Auto-completion
set completeopt=menuone,noselect
set guifont=Your\ Font\ Name:h15
set clipboard+=unnamedplus
let g:compe = {}
let g:compe.enabled = v:true
let g:compe.autocomplete = v:true
let g:compe.debug = v:false
let g:compe.min_length = 1
let g:compe.preselect = 'enable'
let g:compe.throttle_time = 80
let g:compe.source_timeout = 200
let g:compe.resolve_timeout = 800
let g:compe.incomplete_delay = 400
let g:compe.max_abbr_width = 100
let g:compe.max_kind_width = 100
let g:compe.max_menu_width = 100
let g:compe.documentation = v:true

let g:compe.source = {}
let g:compe.source.path = v:true
let g:compe.source.buffer = v:true
let g:compe.source.calc = v:true
let g:compe.source.nvim_lsp = v:true
let g:compe.source.nvim_lua = v:true
let g:compe.source.vsnip = v:true
let g:compe.source.ultisnips = v:true
let g:compe.source.luasnip = v:true
let g:compe.source.emoji = v:true



"statusbar line config
lua << END

-- Eviline config for lualine
-- Author: shadmansaleh
-- Credit: glepnir
local lualine = require('lualine')

-- Color table for highlights
-- stylua: ignore
local colors = {

  bg       = '#000000',
  fg       = '#7c6f64',
 -- fg       = '#76a598',
  yellow   = '#ECBE7B',
  cyan     = '#008080',
  darkblue = '#89a598',   -- set to navy blue
  green    = '#98be65',
  orange   = '#FF8800',
  violet   = '#89a598',   --  set to navyblue
--magenta  = '#bf5a52',   --gruvbox brown
  magenta  = "#c14a4a",   --gruvbox red1 
--magenta  = '#cc241d',
  blue     = '#000000',
  lue     = '#000000',
  red      = '#7c6f64',

    --blue = "#89a598",          -- set to navyblue 
}

local conditions = {
  buffer_not_empty = function()
    return vim.fn.empty(vim.fn.expand('%:t')) ~= 1
  end,
  hide_in_width = function()
    return vim.fn.winwidth(0) > 80
  end,
  check_git_workspace = function()
    local filepath = vim.fn.expand('%:p:h')
    local gitdir = vim.fn.finddir('.git', filepath .. ';')
    return gitdir and #gitdir > 0 and #gitdir < #filepath
  end,
}

-- Config
local config = {
  options = {
    -- Disable sections and component separators
    component_separators = '',
    section_separators = '',
    theme = {
      -- We are going to use lualine_c an lualine_x as left and
      -- right section. Both are highlighted by c theme .  So we
      -- are just setting default looks o statusline
      normal = { c = { fg = colors.fg, bg = colors.bg } },
      inactive = { c = { fg = colors.fg, bg = colors.bg } },
    },
  },
  sections = {
    -- these are to remove the defaults
    lualine_a = {},
    lualine_b = {},
    lualine_y = {},
    lualine_z = {},
    -- These will be filled later
    lualine_c = {},
    lualine_x = {},
  },
  inactive_sections = {
    -- these are to remove the defaults
    lualine_a = {},
    lualine_b = {},
    lualine_y = {},
    lualine_z = {},
    lualine_c = {},
    lualine_x = {},
  },
}

-- Inserts a component in lualine_c at left section
local function ins_left(component)
  table.insert(config.sections.lualine_c, component)
end

-- Inserts a component in lualine_x at right section
local function ins_right(component)
  table.insert(config.sections.lualine_x, component)
end

ins_left {
  function()
    return '▊'
  end,
  color = { fg = colors.blue }, -- Sets highlighting of component
  padding = { left = 0, right = 1 }, -- We don't need space before this
}

ins_left {
  -- mode component
  function()
    return ''
  end,
  color = function()
    -- auto change color according to neovims mode
    local mode_color = {
      n = colors.red,
      i = colors.green,
      v = colors.blue,
      [''] = colors.blue,
      V = colors.blue,
      c = colors.magenta,
      no = colors.red,
      s = colors.orange,
      S = colors.orange,
      [''] = colors.orange,
      ic = colors.yellow,
      R = colors.violet,
      Rv = colors.violet,
      cv = colors.red,
      ce = colors.red,
      r = colors.cyan,
      rm = colors.cyan,
      ['r?'] = colors.cyan,
      ['!'] = colors.red,
      t = colors.red,
    }
    return { fg = mode_color[vim.fn.mode()] }
  end,
  padding = { right = 1 },
}

ins_left {
  -- filesize component
  'filesize',
  cond = conditions.buffer_not_empty,
}

ins_left {
  'filename',
  cond = conditions.buffer_not_empty,
  color = { fg = colors.magenta}, --, gui = 'bold' },
}

ins_left { 'location' }

ins_left { 'progress', color = { fg = colors.fg }} --, gui = 'bold' } }

ins_left {
  'diagnostics',
  sources = { 'nvim_diagnostic' },
  symbols = { error = ' ', warn = ' ', info = ' ' },
  diagnostics_color = {
    color_error = { fg = colors.red },
    color_warn = { fg = colors.yellow },
    color_info = { fg = colors.cyan },
  },
}

-- Insert mid section. You can make any number of sections in neovim :)
-- for lualine it's any number greater then 2
ins_left {
  function()
    return '%='
  end,
}

-- Add components to right sections


--ins_right {
  --'branch',
  --icon = '',
  --color = { fg = colors.violet, gui = 'bold' },
--}

--ins_right {
  --'diff',
  -- Is it me or the symbol for modified us really weird
  --symbols = { added = ' ', modified = '󰝤 ', removed = ' ' },
  --diff_color = {
    --added = { fg = colors.green },
    --modified = { fg = colors.orange },
    --removed = { fg = colors.red },
  --},
  --cond = conditions.hide_in_width,
--}

--ins_right {
  --function()
    --return '▊'
  --end,
  --color = { fg = colors.blue },
  --padding = { left = 1 },
--}

-- Now don't forget to initialize lualine
lualine.setup(config)
require('lualine').setup()
END



