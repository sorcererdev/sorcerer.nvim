-- :checkhealth sorcerer
local M = {}

local install = "cargo install --git https://github.com/sorcererdev/sorcerer scry"

function M.check()
  vim.health.start("sorcerer")
  if vim.fn.has("nvim-0.10") == 0 then vim.health.error("Neovim 0.10 or newer is needed") else vim.health.ok("Neovim " .. tostring(vim.version())) end
  local cmd = ((require("sorcerer").opts or require("sorcerer").defaults).scry or {}).cmd or { "scry", "lsp" }
  local exe = cmd[1]
  if vim.fn.executable(exe) == 0 then
    vim.health.error(("`%s` is not on the path"):format(exe), { "install it: " .. install, "or set scry.cmd in setup()" })
    return
  end
  local out = vim.fn.system({ exe, "--version" })
  if vim.v.shell_error ~= 0 then
    vim.health.error(("`%s --version` failed: %s"):format(exe, vim.trim(out)), { "reinstall it: " .. install })
    return
  end
  vim.health.ok(("%s found: %s"):format(exe, vim.trim(out)))
  vim.health.info('"scry doctor" in a project checks the keys and the models')
end

return M
