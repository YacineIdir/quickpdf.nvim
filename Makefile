# Test entry point. `make test` runs the whole suite in a headless Neovim and
# exits non-zero on failure; `make test TESTS=<file>` runs a single test file.

NVIM ?= nvim
MINI_NVIM_REV ?= v0.18.0
MINI_NVIM_DIR := deps/mini.nvim
TESTS ?=

.PHONY: test deps clean

test: deps
ifeq ($(strip $(TESTS)),)
	$(NVIM) --headless --noplugin -u tests/minit.lua -c "lua MiniTest.run()"
else
	$(NVIM) --headless --noplugin -u tests/minit.lua -c "lua MiniTest.run_file('$(TESTS)')"
endif

deps: $(MINI_NVIM_DIR)

$(MINI_NVIM_DIR):
	git clone --depth 1 --branch $(MINI_NVIM_REV) https://github.com/echasnovski/mini.nvim $@

clean:
	rm -rf deps
