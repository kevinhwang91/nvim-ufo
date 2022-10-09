# Changelog

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
