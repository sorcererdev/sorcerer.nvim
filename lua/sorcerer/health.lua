-- :checkhealth sorcerer
local M = {}

local install = require("sorcerer.program").install.scry
local conjure_install = require("sorcerer.program").install.conjure
local spellbook_install = require("sorcerer.program").install.spellbook

-- The `conjure` section: only when conjure is enabled in setup().
local function check_conjure()
  local conjure = (require("sorcerer").opts or require("sorcerer").defaults).conjure or {}
  if not conjure.enabled then return end
  vim.health.start("sorcerer: conjure")
  local exe = (conjure.cmd or { "conjure", "lsp" })[1]
  if vim.fn.executable(exe) == 0 then
    vim.health.error(("`%s` is not on the path"):format(exe), { "install it: " .. conjure_install, "or set conjure.cmd in setup()" })
    return
  end
  local out = vim.fn.system({ exe, "--version" })
  if vim.v.shell_error ~= 0 then
    vim.health.error(("`%s --version` failed: %s"):format(exe, vim.trim(out)), { "reinstall it: " .. conjure_install })
    return
  end
  vim.health.ok(("%s found: %s"):format(exe, vim.trim(out)))
  vim.health.info('"conjure doctor" in a project checks the models and the trust')
end

-- The `spellbook` section: only when spellbook is enabled in setup().
local function check_spellbook()
  local spellbook = (require("sorcerer").opts or require("sorcerer").defaults).spellbook or {}
  if not spellbook.enabled then return end
  vim.health.start("sorcerer: spellbook")
  local exe = (spellbook.cmd or { "spellbook", "lsp" })[1]
  if vim.fn.executable(exe) == 0 then
    vim.health.error(("`%s` is not on the path"):format(exe), { "install it: " .. spellbook_install, "or set spellbook.cmd in setup()" })
    return
  end
  local out = vim.fn.system({ exe, "--version" })
  if vim.v.shell_error ~= 0 then
    vim.health.error(("`%s --version` failed: %s"):format(exe, vim.trim(out)), { "reinstall it: " .. spellbook_install })
    return
  end
  vim.health.ok(("%s found: %s"):format(exe, vim.trim(out)))
  vim.health.info('"spellbook doctor" in a project checks the generators, the languages and the trust')
end

function M.check()
  vim.health.start("sorcerer")
  if vim.fn.has("nvim-0.10") == 0 then vim.health.error("Neovim 0.10 or newer is needed") else vim.health.ok("Neovim " .. tostring(vim.version())) end
  local cmd = ((require("sorcerer").opts or require("sorcerer").defaults).scry or {}).cmd or { "scry", "lsp" }
  local exe = cmd[1]
  if vim.fn.executable(exe) == 0 then
    vim.health.error(("`%s` is not on the path"):format(exe), { "install it: " .. install, "or set scry.cmd in setup()" })
    check_conjure()
    check_spellbook()
    return
  end
  local out = vim.fn.system({ exe, "--version" })
  if vim.v.shell_error ~= 0 then
    vim.health.error(("`%s --version` failed: %s"):format(exe, vim.trim(out)), { "reinstall it: " .. install })
    return
  end
  vim.health.ok(("%s found: %s"):format(exe, vim.trim(out)))
  vim.health.info('"scry doctor" in a project checks the keys and the models')
  check_conjure()
  check_spellbook()
end

return M
