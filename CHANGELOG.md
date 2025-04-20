# Changelog

## [1.5.0] - 2025-04-07

### 🚀 Features

- Support new api vim.lsp.get_clients (#222)
- *(provider)* Add marker provider (#218)
- *(provider)* Allow using tree-sitter node types as kinds (#243)
- *(decorator)* Redraw folded line with debounce
- *(fold)* Don't auto fold range under cursor for close_fold_kinds_for_ft (#271)

### 🐛 Bug Fixes

- *(decorator)* Only compute folded pairs for current window (#223)
- *(window)* Handle window namespace (#230)
- *(window)* Check cursorline hl before resetting hl (#242)
- *(window)* Record namespace for cursorline (#242)
- *(window)* Skip ns == 0
- *(treesitter)* Attempt to call method 'type' (a nil value) (#254)
- *(window)* Remove comma for list options (#257)
- *(main)* Hint foldmethod for diff or marker
- *(preview)* Don't set `list` option (#258)
- *(decorator)* Suppress error in async function (#260)
- *(decorator)* Always init window model in onWin (#261)
- *(treesitter)* Use new behavior for treesitter iter_matches (#247,#262,#264)
- *(preview)* Attach buffer options for winbar
- *(fold)* Options type changed since v0.10 (#265)
- *(window)* Cursorline under multiple windows (#269)
- *(fold)* Make sure viewoptions contain 'folds' (#274)
- *(treesitter)* Put node type value in MetaNode (#278)
- *(wffi)* Turn jit off for ffi wrapper (#283)
- *(render)* Skip current render cycle if treesitter parsing (#288)
- *(treesitter)* Compatibility with Neovim 0.11 (#286)
- *(coc)* Prevent folds request if coc is disabled for the buffer (#251)

### ⚡ Performance

- *(preview)* Capture highlight asynchronously
- *(provider)* Get fold incremental for indent
- *(provider)* Get fold incremental for marker

## [1.4.0] - 2024-04-03

### 🚀 Features

- *(preview)* Add `jumpTop` and `jumpBot` keymap actions (#109)
- *(highlight)* Add `UfoCursorFoldedLine` (#103)
- *(render)* Support inlay (#155)
- *(render)* Add support for concealed characters (#153) (#156)
- *(api)* Add cursor range and kind information for `UfoInspect`
- *(config)* [**breaking**] Use `close_fold_kinds_for_ft` instead `close_fold_kinds`
- *(decorator)* Export fold kind in `fold_virt_text_handler` (#207)
- *(build)* Luarocks support (#211)

### 🐛 Bug Fixes

- *(preview)* Respect `tabstop` and `shiftwidth` opts
- *(provider)* Respect 'tabstop' and 'shiftwidth' for indent
- *(decorator)* Reset winhl after detach
- *(decorator)* Keep last winid field
- *(driver)* Respect `foldminlines` (#108)
- *(decorator)* Buffer may be changed in a window
- *(decorator)* `setl winhl` erase hl of `nvim_win_set_hl_ns` (#111)
- *(preview)* Dispose preview window even if buffer is wiped out
- *(buffer)* Quickfix buftype can't detect line changed
- *(decorator)* Open fold should redraw at once (#132)
- *(treesitter)* Support `#make-range!` (#139)
- *(preview)* Window height should more than zero
- *(fold)* Refresh fb table in closure function
- Throw UfoFallbackException on RequestFailed (#159)
- *(render)* Join text for default hlgroup (#163)
- *(render)* Skip error return by `synID`
- *(fold)* Sync extmarks with foldedLines (#167)
- *(treesitter)* Use metadata.range prefer (#169)
- *(window)* Clear win highlight if buf changed
- *(decorator)* Ignore redraw request for closing fold (#176)
- *(decorator)* Ignore redundant redraw (#180,#181)
- *(fold)* Scan win folds if one buffer in multiple window
- *(decorator)* Correct bufnrSet logic
- *(window)* Don't clear winhl during first render (#183)
- *(render)* Replace `Normal` highlight with `UfoFoldedFg`
- *(action)* Check endLnum to avoid infinite loop (#184)
- *(decorator)* Highlight open fold for multiple windows correctly (#187)
- *(decorator)* Erase extmark even in multiple windows
- *(decorator)* Narrow the fold range for stale
- *(treesitter)* Fix errors when getting hlId on nvim 0.10.x (#188)
- *(model)* Use private field to avoid inherit (#186)
- *(fold)* Don't make scan flag if manual invoke (#192)
- *(window)* Upstream bug, `set winhl` change curswant (#194)
- *(preview)* Nightly change `nvim_win_get_config` return val
- *(wffi)* `changed_window_setting` signature changed
- *(decorator)* Keep silent for `Keyboard interrupt` error (#202)
- *(decorator)* Correct capture condition
- *(fold)* Return correct winid

### ⚡ Performance

- *(decorator)* Skip rendering of horizontal movement
- *(decorator)* `set winhl` will redraw all lines

## [1.3.0] - 2023-01-05

### Features

#### Provider

- Use fallback if `buftype == 'nofile'`
- Inspect current fold kinds

### Bug Fixes

#### Preview

- Respect target buffer opts
- Stick to top left corner while scrolling in normal window
- Fix wrong row for upward display

#### Fold

- Window maybe changed before set opts
- Improve leaving diff mode behavior

#### Miscellaneous

- Substitute NUL byte for VimScript func
- Catch coc.nvim `Plugin not ready` error and resolve

### Documentation

- Explain `fold_virt_text_handler` (#98)
- Make capabilities for all available lsp servers & remove "other_fields" (#100)

## [1.2.0] - 2022-10-09

### Features

#### Fold

- Add `close_fold_kinds` option
- Make the window display upward if `kind == 'comment'` (#73)

#### API

- Add `applyFolds`
- Add `openFoldsExceptKinds` (#64)

#### Preview

- Support highlighting with `:match`
- Show virtual winbar if preview is scrolled and export `UfoPreviewWinbar` highlight group
- Highlight cursor line for preview and export `UfoPreviewCursorLine` highlight group

#### Decorator

- Hint error for users' virtTextHandler (#79)
- Add `enable_get_fold_virt_text` option to get virt texts of all folded lines (#74)

### !Breaking

- `enable_fold_end_virt_text` option is deprecated, use `enable_get_fold_virt_text` instead
- The signature of `peekFoldedLinesUnderCursor` API is changed

### Bug Fixes

#### Fold

- Handle multiple windows with same buffers
- `set foldenable` forecdly after leaving diff mode
- Restore topline after first applying folds to keep eyes comfortable
- EndLnum may exceed buffer line count because of the asynchronization

#### API

- Action should work after detach (#75)

#### Preview

- Dispose previous resources before a new attach
- Scroll bar reaches the bottom until the end of the line is visible

#### Provider

- Need more time to wait for the server
- Better bypass strategy, must reach the timeout and a certain number of requests
- Lsp provider always returns Promise object
- Validate buffer after requesting folds
- Dispose all providers properly

#### Decorator

- Stop highlighting after opening folds during incsearch
- Keep refreshing even if nofoldenable

#### Render

- Limit the end of range
- Treesitter extmarks may be overlapped, filter invalid extmarks out

## [1.1.0] - 2022-08-13

### Bug Fixes

- Reset foldlines if extmark range is backward
- Unexpected fired `on_lines` at nvim_buf_attach
- Fix `winsaveview()` for scanning fold ranges
- Always open folds if text content in range (#60)
- Scroll bar shouldn't be filled fully if it's scrollable
- Drop coc.nvim cancellation
- Filter out last same ranges
- Assert `provider_selector` return value (#61)

### Features

- Add `closeFoldsWith` API (#62)
- Truncate top border for preview if possible

## [1.0.0] - 2022-07-24

First release with 1.0.0 version.
