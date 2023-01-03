# nvim-ufo

The goal of nvim-ufo is to make Neovim's fold look modern and keep high performance.

<https://user-images.githubusercontent.com/17562139/173796287-9842fb3a-37c2-47fb-8968-6e7600c0fcef.mp4>

> [setup foldcolumn like demo](https://github.com/kevinhwang91/nvim-ufo/issues/4)

---

## Table of contents

- [Table of contents](#table-of-contents)
- [Features](#features)
- [Quickstart](#quickstart)
  - [Requirements](#requirements)
  - [Installation](#installation)
  - [Minimal configuration](#minimal-configuration)
  - [Usage](#usage)
- [Documentation](#documentation)
  - [How does nvim-ufo get the folds?](#how-does-nvim-ufo-get-the-folds)
  - [Setup and description](#setup-and-description)
  - [Preview function table](#preview-function-table)
  - [Commands](#commands)
  - [API](#api)
  - [Highlight groups](#highlight-groups)
- [Advanced configuration](#advanced-configuration)
  - [Customize configuration](#customize-configuration)
  - [Customize fold text](#customize-fold-text)
- [Feedback](#feedback)
- [License](#license)

## Features

- Penetrate color for folded lines like other modern editors/IDEs
- Never block Neovim
- Adding folds high accuracy with Folding Range in LSP
- Support fallback and customize strategy for fold provider
- Peek folded line and jump the desired location with less redraw

## Quickstart

### Requirements

- [Neovim](https://github.com/neovim/neovim) 0.6.1 or later
- [coc.nvim](https://github.com/neoclide/coc.nvim) (optional)
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) (optional)

### Installation

Install with [Packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {'kevinhwang91/nvim-ufo', requires = 'kevinhwang91/promise-async'}
```

### Minimal configuration

```lua
use {'kevinhwang91/nvim-ufo', requires = 'kevinhwang91/promise-async'}

vim.o.foldcolumn = '1' -- '0' is not bad
vim.o.foldlevel = 99 -- Using ufo provider need a large value, feel free to decrease the value
vim.o.foldlevelstart = 99
vim.o.foldenable = true

-- Using ufo provider need remap `zR` and `zM`. If Neovim is 0.6.1, remap yourself
vim.keymap.set('n', 'zR', require('ufo').openAllFolds)
vim.keymap.set('n', 'zM', require('ufo').closeAllFolds)

-- Option 1: coc.nvim as LSP client
use {'neoclide/coc.nvim', branch = 'master', run = 'yarn install --frozen-lockfile'}
require('ufo').setup()
--

-- Option 2: nvim lsp as LSP client
-- Tell the server the capability of foldingRange,
-- Neovim hasn't added foldingRange to default capabilities, users must add it manually
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities.textDocument.foldingRange = {
    dynamicRegistration = false,
    lineFoldingOnly = true
}
local language_servers = require("lspconfig").util.available_servers() -- or list servers manually like {'gopls', 'clangd'}
for _, ls in ipairs(language_servers) do
    require('lspconfig')[ls].setup({
        capabilities = capabilities,
        other_fields = ...
    })
end
require('ufo').setup()
--

-- Option 3: treesitter as a main provider instead
-- Only depend on `nvim-treesitter/queries/filetype/folds.scm`,
-- performance and stability are better than `foldmethod=nvim_treesitter#foldexpr()`
use {'nvim-treesitter/nvim-treesitter', run = ':TSUpdate'}
require('ufo').setup({
    provider_selector = function(bufnr, filetype, buftype)
        return {'treesitter', 'indent'}
    end
})
--

-- Option 4: disable all providers for all buffers
-- Not recommend, AFAIK, the ufo's providers are the best performance in Neovim
require('ufo').setup({
    provider_selector = function(bufnr, filetype, buftype)
        return ''
    end
})
```

### Usage

Use fold as usual.

Using a provider of ufo, must set a large value for `foldlevel`, this is the limitation of
`foldmethod=manual`. A small value may close fold automatically if the fold ranges updated.

After running `zR` and `zM` normal commands will change the `foldlevel`, ufo provide the APIs
`openAllFolds`/`closeAllFolds` to open/close all folds but keep `foldlevel` value, need to remap
them.

Like `zR` and `zM`, if you used `zr` and `zm` before, please use `closeFoldsWith` API to close folds
like `set foldlevel=n` but keep `foldlevel` value.

## Documentation

### How does nvim-ufo get the folds?

If ufo detect `foldmethod` option is not `diff` or `marker`, it will request the providers to get
the folds, the request strategy is formed by the main and the fallback. The default value of main is
`lsp` and the default value of fallback is `indent` which implemented by ufo.

For example, Changing the text in a buffer will request the providers for folds.

> `foldmethod` option will finally become `manual` if ufo is working.

### Setup and description

```lua
{
    open_fold_hl_timeout = {
        description = [[Time in millisecond between the range to be highlgihted and to be cleared
                    while opening the folded line, `0` value will disable the highlight]],
        default = 400
    },
    provider_selector = {
        description = [[A function as a selector for fold providers. For now, there are
                    'lsp' and 'treesitter' as main provider, 'indent' as fallback provider]],
        default = nil
    },
    close_fold_kinds = {
        description = [[After the buffer is displayed (opened for the first time), close the
                    folds whose range with `kind` field is included in this option. For now,
                    'lsp' provider's standardized kinds are 'comment', 'imports' and 'region',
                    run `UfoInspect` for details if your provider has extended the kinds.]],
        default = {}
    },
    fold_virt_text_handler = {
        description = [[A function customize fold virt text, see ### Customize fold text]],
        default = nil
    },
    enable_get_fold_virt_text = {
        description = [[Enable a function with `lnum` as a parameter to capture the virtual text
                    for the folded lines and export the function to `get_fold_virt_text` field of
                    ctx table as 6th parameter in `fold_virt_text_handler`]],
        default = false
    },
    preview = {
        description = [[Configure the options for preview window and remap the keys for current
                    buffer and preview buffer if the preview window is displayed.
                    Never worry about the users's keymaps are overridden by ufo, ufo will save
                    them and restore them if preview window is closed.]],
        win_config = {
            border = {
                description = [[The border for preview window,
                    `:h nvim_open_win() | call search('border:')`]],
                default = 'rounded',
            },
            winblend = {
                description = [[The winblend for preview window, `:h winblend`]],
                default = 12,
            },
            winhighlight = {
                description = [[The winhighlight for preview window, `:h winhighlight`]],
                default = 'Normal:Normal',
            },
            maxheight = {
                description = [[The max height of preview window]],
                default = 20,
            }
        },
        mappings = {
            description = [[The table for {function = key}]],
            default = [[see ###Preview function table for detail]],
        }
    }
}
```

`:h ufo` may help you to get the all default configuration.

### Preview function table

<!-- markdownlint-disable MD013 -->

| Function | Action                                                                                         | Def Key |
| -------- | ---------------------------------------------------------------------------------------------- | ------- |
| scrollB  | Type `CTRL-B` in preview window                                                                |         |
| scrollF  | Type `CTRL-F` in preview window                                                                |         |
| scrollU  | Type `CTRL-U` in preview window                                                                |         |
| scrollD  | Type `CTRL-D` in preview window                                                                |         |
| scrollE  | Type `CTRL-E` in preview window                                                                | `<C-E>` |
| scrollY  | Type `CTRL-Y` in preview window                                                                | `<C-Y>` |
| close    | In normal window: Close preview window<br>In preview window: Close preview window              | `q`     |
| switch   | In normal window: Go to preview window<br>In preview window: Go to normal window               | `<Tab>` |
| trace    | In normal window: Trace code based on topline<br>In preview window: Trace code based on cursor | `<CR>`  |

<!-- markdownlint-enable MD013-->

Additional mouse supported:

1. `<ScrollWheelUp>` and `<ScrollWheelDown>`: Scroll preview window.
2. `<2-LeftMouse>`: Same as `trace` action in preview window.

> `trace` action will open all fold for the folded lines

### Commands

| Command        | Description                                                    |
| -------------- | -------------------------------------------------------------- |
| UfoEnable      | Enable ufo                                                     |
| UfoDisable     | Disable ufo                                                    |
| UfoInspect     | Inspect current buffer information                             |
| UfoAttach      | Attach current buffer to enable all features                   |
| UfoDetach      | Detach current buffer to disable all features                  |
| UfoEnableFold  | Enable to get folds and update them at once for current buffer |
| UfoDisableFold | Disable to get folds for current buffer                        |

### API

[ufo.lua](./lua/ufo.lua)

### Highlight groups

```vim
" hi default UfoFoldedFg guifg=Normal.foreground
" hi default UfoFoldedBg guibg=Folded.background
hi default link UfoPreviewSbar PmenuSbar
hi default link UfoPreviewThumb PmenuThumb
hi default link UfoPreviewWinBar UfoFoldedBg
hi default link UfoPreviewCursorLine Visual
hi default link UfoFoldedEllipsis Comment
```

- `UfoFoldedFg`: Foreground for raw text of folded line.
- `UfoFoldedBg`: Background of folded line.
- `UfoPreviewSbar`: Scroll bar of preview window, only take effect if the border is missing right
  horizontal line, like `border = 'none'`.
- `UfoPreviewCursorLine`: Highlight current line in preview window if it isn't the start of folded
  lines.
- `UfoPreviewWinBar`: Virtual winBar of preview window.
- `UfoPreviewThumb`: Thumb of preview window.
- `UfoFoldedEllipsis`: Ellipsis at the end of folded line, invalid if `fold_virt_text_handler` is
  set.

## Advanced configuration

Configuration can be found at [example.lua](./doc/example.lua)

### Customize configuration

```lua
local ftMap = {
    vim = 'indent',
    python = {'indent'},
    git = ''
}
require('ufo').setup({
    open_fold_hl_timeout = 150,
    close_fold_kinds = {'imports', 'comment'},
    preview = {
        win_config = {
            border = {'', '─', '', '', '', '─', '', ''},
            winhighlight = 'Normal:Folded',
            winblend = 0
        },
        mappings = {
            scrollU = '<C-u>',
            scrollD = '<C-d>'
        }
    },
    provider_selector = function(bufnr, filetype, buftype)
        -- if you prefer treesitter provider rather than lsp,
        -- return ftMap[filetype] or {'treesitter', 'indent'}
        return ftMap[filetype]

        -- refer to ./doc/example.lua for detail
    end
})
vim.keymap.set('n', 'zR', require('ufo').openAllFolds)
vim.keymap.set('n', 'zM', require('ufo').closeAllFolds)
vim.keymap.set('n', 'zr', require('ufo').openFoldsExceptKinds)
vim.keymap.set('n', 'zm', require('ufo').closeFoldsWith) -- closeAllFolds == closeFoldsWith(0)
vim.keymap.set('n', 'K', function()
    local winid = require('ufo').peekFoldedLinesUnderCursor()
    if not winid then
        -- choose one of coc.nvim and nvim lsp
        vim.fn.CocActionAsync('definitionHover') -- coc.nvim
        vim.lsp.buf.hover()
    end
end)
```

### Customize fold text

Adding number suffix of folded lines instead of the default ellipsis, here is the example:

<p align="center">
    <img width="864px" src=https://user-images.githubusercontent.com/17562139/174121926-e90a962d-9fc9-428a-bd53-274ed392c68d.png>
</p>

```lua
local handler = function(virtText, lnum, endLnum, width, truncate)
    local newVirtText = {}
    local suffix = ('  %d '):format(endLnum - lnum)
    local sufWidth = vim.fn.strdisplaywidth(suffix)
    local targetWidth = width - sufWidth
    local curWidth = 0
    for _, chunk in ipairs(virtText) do
        local chunkText = chunk[1]
        local chunkWidth = vim.fn.strdisplaywidth(chunkText)
        if targetWidth > curWidth + chunkWidth then
            table.insert(newVirtText, chunk)
        else
            chunkText = truncate(chunkText, targetWidth - curWidth)
            local hlGroup = chunk[2]
            table.insert(newVirtText, {chunkText, hlGroup})
            chunkWidth = vim.fn.strdisplaywidth(chunkText)
            -- str width returned from truncate() may less than 2nd argument, need padding
            if curWidth + chunkWidth < targetWidth then
                suffix = suffix .. (' '):rep(targetWidth - curWidth - chunkWidth)
            end
            break
        end
        curWidth = curWidth + chunkWidth
    end
    table.insert(newVirtText, {suffix, 'MoreMsg'})
    return newVirtText
end

-- global handler
-- `handler` is the 2nd parameter of `setFoldVirtTextHandler`,
-- check out `./lua/ufo.lua` and search `setFoldVirtTextHandler` for detail.
require('ufo').setup({
    fold_virt_text_handler = handler
})

-- buffer scope handler
-- will override global handler if it is existed
-- local bufnr = vim.api.nvim_get_current_buf()
-- require('ufo').setFoldVirtTextHandler(bufnr, handler)
```

## Feedback

- If you get an issue or come up with an awesome idea, don't hesitate to open an issue in github.
- If you think this plugin is useful or cool, consider rewarding it a star.

## License

The project is licensed under a BSD-3-clause license. See [LICENSE](./LICENSE) file for details.
