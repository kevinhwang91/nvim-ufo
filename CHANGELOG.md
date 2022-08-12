# Changelog

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
