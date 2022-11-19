SHELL := /bin/bash
DEPS ?= build

LUA_LS ?= $(DEPS)/lua-language-server
LINT_LEVEL ?= Information

all:

lint:
	@rm -rf $(LUA_LS)
	@mkdir -p $(LUA_LS)
	@VIM=$(HOME)/.local/share/nvim lua-language-server --check $(PWD) --checklevel=$(LINT_LEVEL) --logpath=$(LUA_LS)
	@[[ -f $(LUA_LS)/check.json ]] && { cat $(LUA_LS)/check.json 2>/dev/null; exit 1; } || true

clean:
	rm -rf $(DEPS)

.PHONY: all deps clean lint
