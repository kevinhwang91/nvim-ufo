# nvim-ufo

Not UFO in the sky, but an ultra fold in Neovim.

The goal of nvim-ufo is to make Neovim's fold look modern and keep high performance.

**WIP this week**, setup may change.

<https://user-images.githubusercontent.com/17562139/173796287-9842fb3a-37c2-47fb-8968-6e7600c0fcef.mp4>

---

## Table of contents

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
vim.wo.foldlevel = 99 -- free feel to decrease the value
vim.wo.foldenable = true

-- option 1: coc.nvim as LSP client
use {'neoclide/coc.nvim', branch = 'master', run = 'yarn install --frozen-lockfile'}

-- option 2: nvim lsp as LSP client
-- tell the sever the capability of foldingRange
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities.textDocument.foldingRange = {
    dynamicRegistration = false,
    lineFoldingOnly = true
}

require('ufo').setup()
```

### Usage

Use fold as usual.

## Documentation

### How does nvim-ufo get the folds?

If ufo detect `foldmethod` option is not `diff` or `marker`, it will request the providers to get
the folds, the request strategy formed by the main and the fallback. The default value of main is
`lsp` and the default value of fallback is `indent` which implemented by ufo.

Changing the text in a buffer will request the providers for folds.

### Setup and description

```lua
{
    open_fold_hl_timeout = {
        description = [[time in millisecond between the range to be highlgihted and to be cleared
                    while opening the folded line, `0` value will disable the highlight]],
        default = 400
    },
    provider_selector = {
        description = [[a function as a selector for fold providers, TODO]],
        default = nil
    }
}
```

### Highlight groups

```vim
hi default link UfoFoldedEllipsis Comment
```

- `UfoFoldedEllipsis`: highlight ellipsis as the end of folded line

## Advanced configuration

### Customize configuration

## Feedback

- If you get an issue or come up with an awesome idea, don't hesitate to open an issue in github.
- If you think this plugin is useful or cool, consider rewarding it a star.

## License

The project is licensed under a BSD-3-clause license. See [LICENSE](./LICENSE) file for details.
