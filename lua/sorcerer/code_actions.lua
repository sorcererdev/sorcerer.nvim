-- Code actions in the order an editor shows fixes: the preferred quick fixes first, then the
-- other quick fixes, then everything else, each group in the order the servers gave it.
-- Neovim's menu lists each server's actions in the order the servers happen to come, so a
-- rule's fix could sit below a rewrite. Nothing here names a server: a server marks its fix
-- with the LSP's own `kind = "quickfix"` and `isPreferred`, as VS Code reads them.
local M = {}

-- the wrappers made here, so wrapping one again is a no-op
local wrappers = setmetatable({}, { __mode = "k" })

local function group_of(action)
  if action.isPreferred then return 1 end
  local kind = action.kind or ""
  if kind == "quickfix" or vim.startswith(kind, "quickfix.") then return 2 end
  return 3
end

-- The menu's items (each `{ action = …, ctx = … }`) reordered: preferred quick fixes, quick
-- fixes, the rest; the order within a group is kept.
-- Example: { rewrite, fix, preferred fix } becomes { preferred fix, fix, rewrite }.
function M.ordered(items)
  local groups = { {}, {}, {} }
  for _, item in ipairs(items) do
    local action = type(item) == "table" and (item.action or item) or {}
    table.insert(groups[group_of(action)], item)
  end
  local out = {}
  for _, group in ipairs(groups) do vim.list_extend(out, group) end
  return out
end

-- `select` wrapped so that the code-action menu gets its items in order; every other menu is
-- passed through untouched.
function M.wrap(select)
  if type(select) ~= "function" or wrappers[select] then return select end
  local function ordered_select(items, opts, on_choice)
    if opts and opts.kind == "codeaction" and type(items) == "table" then items = M.ordered(items) end
    return select(items, opts, on_choice)
  end
  wrappers[ordered_select] = true
  return ordered_select
end

-- Wraps vim.ui.select now and again whenever a server attaches, since a picker plugin set up
-- after this (snacks, telescope, fzf-lua) puts its own select in place. `enabled = false` leaves
-- the menu as Neovim makes it.
function M.setup(enabled)
  local group = vim.api.nvim_create_augroup("sorcerer_code_actions", { clear = true })
  if not enabled then return end
  local function ensure() vim.ui.select = M.wrap(vim.ui.select) end
  ensure()
  vim.api.nvim_create_autocmd("LspAttach", { group = group, callback = ensure })
end

return M
