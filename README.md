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
  - [How does nvim-ufo get the folds?](#how-does-nvim-ufo-get-the-folds?)
  - [Setup and description](#setup-and-description)
  - [Commands](#commands)
  - [API](#api)
  - [Highlight groups](#highlight-groups)
- [Advanced configuration](#advanced-configuration)
  - [Customize provider selector](#customize-provider-selector)
  - [Customize fold text](#customize-fold-text)
- [Feedback](#feedback)
- [License](#license)

## Features

- Penetrate color for folded lines like other modern editors/IDEs
- Never block Neovim
- Adding folds high accuracy with Folding Range in LSP
- Support Fallback and customize strategy for fold provider

## Quickstart

### Requirements

- [Neovim](https://github.com/neovim/neovim) 0.6.1 or later
- [coc.nvim](https://github.com/neoclide/coc.nvim) (optional)

### Installation

Install with [Packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {'kevinhwang91/nvim-ufo', requires = 'kevinhwang91/promise-async'}
```

### Minimal configuration

```lua
use {'kevinhwang91/nvim-ufo', requires = 'kevinhwang91/promise-async'}

vim.wo.foldcolumn = '1'
vim.wo.foldlevel = 99 -- feel free to decrease the value
vim.wo.foldenable = true

-- option 1: coc.nvim as LSP client
use {'neoclide/coc.nvim', branch = 'master', run = 'yarn install --frozen-lockfile'}
--

-- option 2: nvim lsp as LSP client
-- tell the server the capability of foldingRange
-- nvim hasn't added foldingRange to default capabilities, users must add it manually
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities.textDocument.foldingRange = {
    dynamicRegistration = false,
    lineFoldingOnly = true
}
for _, lsp in ipairs({your_servers}) do
    require('lspconfig').setup({
        capabilities = capabilities,
        others_fields = ...
    })
end
--

require('ufo').setup()
```

### Usage

Use fold as usual.

## Documentation

### How does nvim-ufo get the folds?

If ufo detect `foldmethod` option is not `diff` or `marker`, it will request the providers to get
the folds, the request strategy is formed by the main and the fallback. The default value of main is
`lsp` and the default value of fallback is `indent` which implemented by ufo.

Changing the text in a buffer will request the providers for folds.

> `foldmethod` option will finally become `manual` if ufo are working.

### Setup and description

```lua
{
    open_fold_hl_timeout = {
        description = [[time in millisecond between the range to be highlgihted and to be cleared
                    while opening the folded line, `0` value will disable the highlight]],
        default = 400
    },
    provider_selector = {
        description = [[a function as a selector for fold providers. For now, there are
                    'lsp' and 'indent' providers]],
        default = nil
    },
    fold_virt_text_handler = {
        description = [[a function customize fold virt text, see ### Customize fold text]],
        default = nil
    }
}
```

### Commands

TODO [main.lua](./lua/ufo/main.lua)

### API

TODO [ufo.lua](./lua/ufo.lua)

### Highlight groups

```vim
hi default link UfoFoldedEllipsis Comment
```

- `UfoFoldedEllipsis`: highlight ellipsis at the end of folded line, invalid if
  `fold_virt_text_handler` is set.

## Advanced configuration

Configuration can be found at [example.lua](./doc/example.lua)

### Customize provider selector

```lua
local ftMap = {
    vim = 'indent',
    python = {'indent'},
    git = ''
}
require('ufo').setup({
    provider_selector = function(bufnr, filetype)
        -- return a string type use internal providers
        -- return a string in a table like a string type
        -- return empty string '' will disable any providers
        -- return `nil` will use default value {'lsp', 'indent'}
        return ftMap[filetype]
    end
})
```

### Customize fold text

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
require('ufo').setup({
    fold_virt_text_handler = handler
})

-- buffer scope handler
-- will override global handler if it is existed
local bufnr = vim.api.nvim_get_current_buf()
require('ufo').setFoldVirtTextHandler(bufnr, handler)
```

## Feedback

- If you get an issue or come up with an awesome idea, don't hesitate to open an issue in github.
- If you think this plugin is useful or cool, consider rewarding it a star.

## License

The project is licensed under a BSD-3-clause license. See [LICENSE](./LICENSE) file for details.
