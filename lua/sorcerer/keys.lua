-- sorcerer's keys, all under one prefix (`<leader>m`): conjure here, undo, try harder, why,
-- `:Spellbook new`, `:Spellbook fix` and `:Spellbook check`. Each runs the same code action the server offers,
-- so a line offers exactly what it did before. A key you already mapped is never overwritten:
-- it is skipped and `:checkhealth sorcerer` lists it. `keys = false` binds nothing.
local M = {}

-- name -> { mode(s), tool that must be on, action title or command, description }
local table_of_keys = {
  { name = "new", modes = { "n" }, tool = "spellbook", cmd = "Spellbook new", desc = "sorcerer: new from a generator" },
  { name = "conjure", modes = { "n", "v" }, tool = "conjure", title = "Conjure here", desc = "sorcerer: conjure here" },
  { name = "undo", modes = { "n" }, tool = "conjure", title = "conjure: Undo", desc = "sorcerer: undo the conjured change" },
  { name = "try_harder", modes = { "n" }, tool = "conjure", title = "conjure: Try harder", desc = "sorcerer: try the change again, harder" },
  { name = "why", modes = { "n" }, tool = "conjure", title = "conjure: Show why", desc = "sorcerer: why this change" },
  { name = "fix", modes = { "n" }, tool = "spellbook", fix = true, desc = "sorcerer: apply the finding's fix" },
  { name = "check", modes = { "n" }, tool = "spellbook", cmd = "Spellbook check", desc = "sorcerer: check the project's rules" },
}

local bound, skipped = {}, {}

-- Run the code action titled TITLE on the cursor's line (or the selection), and no other.
-- Example: code_action_titled("conjure: Undo") applies only that action.
local function code_action_titled(title)
  vim.lsp.buf.code_action({
    apply = true,
    filter = function(action) return action.title == title end,
  })
end

-- Take back the maps this module made (only those still ours: a key you mapped since is left).
local function unbind_ours()
  for _, one in ipairs(bound) do
    for _, mode in ipairs(one.modes) do
      if vim.fn.maparg(one.lhs, mode, false, true).desc == one.desc then pcall(vim.keymap.del, mode, one.lhs) end
    end
  end
  bound, skipped = {}, {}
end

local function taken(lhs, modes)
  for _, mode in ipairs(modes) do
    if vim.fn.maparg(lhs, mode) ~= "" then return true end
  end
  return false
end

-- OPTS is the whole setup table: its `keys` (a table, or false for none) and which tools are on.
function M.setup(opts)
  unbind_ours()
  local keys = opts.keys
  if not keys then return end
  for _, one in ipairs(table_of_keys) do
    local key = keys[one.name]
    local tool = opts[one.tool] or {}
    if key and tool.enabled then
      local lhs = (keys.prefix or "<leader>m") .. key
      if taken(lhs, one.modes) then
        table.insert(skipped, { name = one.name, lhs = lhs })
      else
        local run = one.cmd and function() vim.cmd(one.cmd) end
          or one.fix and function() require("sorcerer.spellbook").fix_here() end
          or function() code_action_titled(one.title) end
        vim.keymap.set(one.modes, lhs, run, { desc = one.desc })
        table.insert(bound, { name = one.name, lhs = lhs, modes = one.modes, desc = one.desc })
      end
    end
  end
end

-- The key bound to NAME ("conjure", "undo", …), as written (`<leader>mc`), or nil.
function M.lhs(name)
  for _, one in ipairs(bound) do
    if one.name == name then return one.lhs end
  end
end

-- The keys not bound because the lhs was already mapped: { { name, lhs } }.
function M.skipped()
  return vim.deepcopy(skipped)
end

-- The keys bound: { { name, lhs } }.
function M.bound()
  return vim.tbl_map(function(one) return { name = one.name, lhs = one.lhs } end, bound)
end

return M
