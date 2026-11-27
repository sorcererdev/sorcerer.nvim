-- Code actions in the order an editor shows fixes: each server's fixes together, its preferred
-- quick fix first, the servers with a preferred fix before those without; then everything else,
-- in the order the servers gave it. Neovim's menu lists each server's actions in the order the
-- servers happen to come, so a rule's fix could sit below a rewrite, and a second server's
-- preferred fix could split the first's two fixes. Nothing here names a server: a server marks
-- its fix with the LSP's own `kind = "quickfix"` and `isPreferred`, as VS Code reads them.
local M = {}

-- the wrappers made here, so wrapping one again is a no-op
local wrappers = setmetatable({}, { __mode = "k" })

local function is_fix(action)
  local kind = action.kind or ""
  return action.isPreferred or kind == "quickfix" or vim.startswith(kind, "quickfix.")
end

local function action_of(item)
  return type(item) == "table" and (item.action or item) or {}
end

local function server_of(item)
  return type(item) == "table" and type(item.ctx) == "table" and item.ctx.client_id or false
end

-- One server's fixes, its preferred ones first, each part in the order given.
local function preferred_first(fixes)
  local preferred, others = {}, {}
  for _, item in ipairs(fixes) do
    table.insert(action_of(item).isPreferred and preferred or others, item)
  end
  return vim.list_extend(preferred, others)
end

-- The menu's items (each `{ action = …, ctx = … }`) reordered: each server's fixes together
-- (preferred first), servers with a preferred fix first, then the rest; the order is otherwise
-- kept.
-- Example: { rewrite, fix A2, preferred A1, preferred B1, fix B2 } (A and B two servers)
-- becomes { A1, A2, B1, B2, rewrite }.
function M.ordered(items)
  local fixes_by_server, servers, rest = {}, {}, {}
  for _, item in ipairs(items) do
    if is_fix(action_of(item)) then
      local server = server_of(item)
      if not fixes_by_server[server] then
        fixes_by_server[server] = {}
        table.insert(servers, server)
      end
      table.insert(fixes_by_server[server], item)
    else
      table.insert(rest, item)
    end
  end
  local blocks = vim.tbl_map(function(server) return preferred_first(fixes_by_server[server]) end, servers)
  local with_preferred = vim.tbl_filter(function(b) return action_of(b[1]).isPreferred end, blocks)
  local without = vim.tbl_filter(function(b) return not action_of(b[1]).isPreferred end, blocks)
  local out = {}
  for _, block in ipairs(vim.list_extend(with_preferred, without)) do vim.list_extend(out, block) end
  return vim.list_extend(out, rest)
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
