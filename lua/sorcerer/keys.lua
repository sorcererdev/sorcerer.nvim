-- sorcerer's keys, all under one prefix (`<leader>m`): conjure here, undo, try harder, why,
-- `:Spellbook new`, `:Spellbook fix`, `:Spellbook sync` and `:Spellbook check`, and apprentice's do this, stop,
-- show diff, undo the task, journal, dismiss and label. Each runs the same code action the server offers,
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
  { name = "sync", modes = { "n" }, tool = "spellbook", cmd = "Spellbook sync", desc = "sorcerer: sync the owned regions" },
  { name = "do", modes = { "n" }, tool = "apprentice", title = "apprentice: do this", prefix = true, desc = "sorcerer: apprentice, do this" },
  { name = "stop", modes = { "n" }, tool = "apprentice", title = "apprentice: Stop this task", desc = "sorcerer: stop apprentice's task" },
  { name = "diff", modes = { "n" }, tool = "apprentice", title = "apprentice: Show diff", desc = "sorcerer: the task's diff of this file" },
  { name = "undo_task", modes = { "n" }, tool = "apprentice", title = "apprentice: Undo this task", desc = "sorcerer: undo apprentice's task" },
  { name = "journal", modes = { "n" }, tool = "apprentice", title = "apprentice: Show journal", desc = "sorcerer: apprentice's journal of the task" },
  { name = "dismiss", modes = { "n" }, tool = "apprentice", title = "apprentice: Dismiss", desc = "sorcerer: dismiss apprentice's mark" },
  { name = "label", modes = { "n" }, tool = "apprentice", title = "apprentice: this was", prefix = true, choose = true, desc = "sorcerer: label what this line was" },
}

local bound, skipped = {}, {}

-- Run the code action titled TITLE on the cursor's line (or the selection), and no other.
-- With PREFIX, any action whose title starts with TITLE (an offer carries its price); with
-- CHOOSE, the matching actions are listed to pick from instead of the first one applied.
-- Example: code_action_titled("conjure: Undo") applies only that action.
local function code_action_titled(title, prefix, choose)
  local matches = function(action)
    if prefix then return action.title:sub(1, #title) == title end
    return action.title == title
  end
  vim.lsp.buf.code_action({ apply = not choose, filter = matches })
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
          or function() code_action_titled(one.title, one.prefix, one.choose) end
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
