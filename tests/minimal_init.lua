-- Headless test init: this plugin and plenary (from lazy.nvim's dir or DEPS).
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local deps = vim.env.DEPS or (vim.fn.stdpath("data") .. "/lazy")
vim.opt.rtp:prepend(root)
vim.opt.rtp:prepend(deps .. "/plenary.nvim")
vim.cmd("runtime plugin/plenary.vim")
vim.opt.swapfile = false
-- Test Neovims run at once (make test): never share a ShaDa file.
vim.opt.shadafile = "NONE"
-- A spec that fails before its tests run must end its Neovim, not hang it.
local ok, busted = pcall(require, "plenary.busted")
if ok and not busted._sorcerer_guarded then
  local run = busted.run
  busted.run = function(...)
    local fine, err = pcall(run, ...)
    if not fine then
      io.stderr:write(tostring(err) .. "\n")
      os.exit(1)
    end
  end
  busted._sorcerer_guarded = true
end
