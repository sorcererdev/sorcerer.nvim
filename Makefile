INIT = tests/minimal_init.lua

# Each spec file in its own Neovim, all at once. Needs plenary.nvim (DEPS, else lazy.nvim's dir).
test:
	nvim --headless --noplugin -u $(INIT) -c "PlenaryBustedDirectory tests { minimal_init = '$(INIT)', timeout = 120000 }"

.PHONY: test
