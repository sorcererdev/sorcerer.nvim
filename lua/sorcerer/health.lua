-- :checkhealth sorcerer
local M = {}

local install = require("sorcerer.program").install.scry
local conjure_install = require("sorcerer.program").install.conjure
local spellbook_install = require("sorcerer.program").install.spellbook
local lackey_install = require("sorcerer.program").install.lackey

-- The `lackey` section: only when lackey is enabled in setup().
local function check_lackey()
  local lackey = (require("sorcerer").opts or require("sorcerer").defaults).lackey or {}
  if not lackey.enabled then return end
  vim.health.start("lackey")
  local exe = (lackey.cmd or { "lackey", "lsp" })[1]
  if vim.fn.executable(exe) == 0 then
    vim.health.error(("`%s` is not on the path"):format(exe), { "install it: " .. lackey_install, "or set lackey.cmd in setup()", "or turn it off: lackey = { enabled = false } in setup()" })
    return
  end
  local out = vim.fn.system({ exe, "--version" })
  if vim.v.shell_error ~= 0 then
    vim.health.error(("`%s --version` failed: %s"):format(exe, vim.trim(out)), { "reinstall it: " .. lackey_install })
    return
  end
  vim.health.ok(("%s found: %s"):format(exe, vim.trim(out)))
  vim.health.info('"lackey doctor" in a project checks claude, Jev and the trust')
end

-- The `conjure` section: only when conjure is enabled in setup().
local function check_conjure()
  local conjure = (require("sorcerer").opts or require("sorcerer").defaults).conjure or {}
  if not conjure.enabled then return end
  vim.health.start("conjure")
  local exe = (conjure.cmd or { "conjure", "lsp" })[1]
  if vim.fn.executable(exe) == 0 then
    vim.health.error(("`%s` is not on the path"):format(exe), { "install it: " .. conjure_install, "or set conjure.cmd in setup()", "or turn it off: conjure = { enabled = false } in setup()" })
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
  vim.health.start("spellbook")
  local exe = (spellbook.cmd or { "spellbook", "lsp" })[1]
  if vim.fn.executable(exe) == 0 then
    vim.health.error(("`%s` is not on the path"):format(exe), { "install it: " .. spellbook_install, "or set spellbook.cmd in setup()", "or turn it off: spellbook = { enabled = false } in setup()" })
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

-- The `keys` section: what is bound, and what was skipped because you had mapped it.
local function check_keys()
  local keys = require("sorcerer.keys")
  local bound, skipped = keys.bound(), keys.skipped()
  local unknown = keys.unknown()
  if #bound == 0 and #skipped == 0 and #unknown == 0 then return end
  vim.health.start("keys")
  for _, one in ipairs(bound) do vim.health.ok(("%s is %s"):format(one.name, one.lhs)) end
  for _, one in ipairs(skipped) do
    vim.health.warn(("%s: %s is already mapped, left alone"):format(one.name, one.lhs), { "map another key in setup(): keys = { " .. one.name .. ' = "<key>" }' })
  end
  for _, name in ipairs(unknown) do
    vim.health.warn(("keys.%s is not one of sorcerer's keys, so it binds nothing"):format(name),
      { "the keys were renamed when they were grouped by product: see the keys table in the README" })
  end
end

-- scry, in the main section: off (`scry = { enabled = false }`) is said, not an error, so a
-- lackey-only setup checks clean.
local function check_scry()
  local scry = (require("sorcerer").opts or require("sorcerer").defaults).scry or {}
  if scry.enabled == false then
    vim.health.info("scry is off (scry = { enabled = false })")
    return
  end
  local exe = (scry.cmd or { "scry", "lsp" })[1]
  if vim.fn.executable(exe) == 0 then
    vim.health.error(("`%s` is not on the path"):format(exe), { "install it: " .. install, "or set scry.cmd in setup()", "or turn it off: scry = { enabled = false } in setup()" })
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

function M.check()
  check_keys()
  vim.health.start("sorcerer")
  if vim.fn.has("nvim-0.10") == 0 then vim.health.error("Neovim 0.10 or newer is needed") else vim.health.ok("Neovim " .. tostring(vim.version())) end
  check_scry()
  check_conjure()
  check_spellbook()
  check_lackey()
end

return M
