-- sorcerer's keys, all under one prefix (`<leader>m`), grouped by product:
--
--   <leader>m   the common ones: a do this (lackey) · f fix this · g generate… (spellbook) ·
--               n next step (conjure) · u undo the last change · w why is this flagged? (scry) ·
--               q stop the running task (lackey)
--   <leader>ms  scry: w why · r review this file now · x dismiss · l list findings · c show code
--   <leader>mc  conjure: n next step · t try the change again with more effort · u undo · w why
--   <leader>mb  spellbook: g generate · f fix · k check this file · s sync regions · h list holes
--   <leader>ml  lackey: a do this · q stop · d show the diff · z undo the task · j journal ·
--               o open the answer · x dismiss · l label what you wrote
--
-- A key that runs a server's action runs the same code action the server offers on the line,
-- so a line offers exactly what it did before. A key you already mapped is never overwritten:
-- it is skipped and `:checkhealth sorcerer` lists it. `keys = false` binds nothing; one name
-- set to `false` binds nothing for it. With which-key installed, each prefix is named after its
-- product (`<leader>ms` is "scry").
local M = {}

local writers = { "conjure", "lackey", "spellbook" }
local any_tool = { "scry", "conjure", "lackey", "spellbook" }

-- what to say when lackey's line has no offer: Neovim's "No code actions available" reads as if
-- the key were broken
local no_offer = "lackey: no offer on this line: it was not read as an instruction. Ask for something new (`# Add a median(prices) function …`) or label it (`lackey: this was an instruction`)"

-- Every key, in the order :checkhealth lists them. `key` is what follows the prefix; `tool` is
-- the tool that must be on (a list: any one of them); then what the key runs: a server's action
-- by `title` (`prefix`: a title that starts so; `choose`: pick among the matches; `none`: what
-- to say when the line has none), a `cmd`, or a named `run` below.
M.table_of_keys = {
  -- the common keys, right under the prefix
  { name = "do", key = "a", tool = "lackey", title = "lackey: do this", prefix = true, none = no_offer, desc = "do this" },
  { name = "fix", key = "f", tool = any_tool, run = "fix_this", desc = "fix this" },
  { name = "generate", key = "g", tool = "spellbook", cmd = "Spellbook new", desc = "generate…" },
  { name = "next_step", key = "n", modes = { "n", "v" }, tool = "conjure", title = "Conjure here", desc = "next step" },
  { name = "undo", key = "u", tool = writers, run = "undo_last", desc = "undo the last change" },
  { name = "why", key = "w", tool = "scry", title = "scry: Show why", none = "scry: no finding on this line", desc = "why is this flagged?" },
  { name = "stop", key = "q", tool = "lackey", title = "lackey: Stop this task", desc = "stop the running task" },
  -- scry
  { name = "scry_why", key = "sw", tool = "scry", title = "scry: Show why", none = "scry: no finding on this line", desc = "why is this flagged?" },
  { name = "scry_review", key = "sr", tool = "scry", run = "review", desc = "review this file now" },
  { name = "scry_dismiss", key = "sx", tool = "scry", title = "scry: Dismiss", prefix = true, choose = true, none = "scry: no finding on this line", desc = "dismiss the finding" },
  { name = "scry_list", key = "sl", tool = "scry", run = "list_findings", desc = "list findings" },
  { name = "scry_code", key = "sc", tool = "scry", title = "scry: Show code", none = "scry: no finding on this line cites code", desc = "show the code it cites" },
  -- conjure
  { name = "conjure_next", key = "cn", modes = { "n", "v" }, tool = "conjure", title = "Conjure here", desc = "next step" },
  { name = "conjure_try_again", key = "ct", tool = "conjure", title = "conjure: Try harder", desc = "try the change again with more effort" },
  { name = "conjure_undo", key = "cu", tool = "conjure", title = "conjure: Undo", desc = "undo the change" },
  { name = "conjure_why", key = "cw", tool = "conjure", title = "conjure: Show why", desc = "why this step" },
  -- spellbook
  { name = "spellbook_generate", key = "bg", tool = "spellbook", cmd = "Spellbook new", desc = "generate…" },
  { name = "spellbook_fix", key = "bf", tool = "spellbook", run = "spellbook_fix", desc = "fix" },
  { name = "spellbook_check", key = "bk", tool = "spellbook", run = "check_file", desc = "check this file" },
  { name = "spellbook_sync", key = "bs", tool = "spellbook", cmd = "Spellbook sync", desc = "sync regions" },
  { name = "spellbook_holes", key = "bh", tool = "spellbook", cmd = "Spellbook holes", desc = "list holes" },
  -- lackey
  { name = "lackey_do", key = "la", tool = "lackey", title = "lackey: do this", prefix = true, none = no_offer, desc = "do this" },
  { name = "lackey_stop", key = "lq", tool = "lackey", title = "lackey: Stop this task", desc = "stop" },
  { name = "lackey_diff", key = "ld", tool = "lackey", title = "lackey: Show diff", desc = "show the diff" },
  { name = "lackey_undo", key = "lz", tool = "lackey", title = "lackey: Undo this task", desc = "undo the task" },
  { name = "lackey_journal", key = "lj", tool = "lackey", title = "lackey: Show journal", desc = "journal" },
  { name = "lackey_open_answer", key = "lo", tool = "lackey", title = "lackey: Open the answer", desc = "open the answer" },
  { name = "lackey_dismiss", key = "lx", tool = "lackey", title = "lackey: Dismiss", desc = "dismiss" },
  { name = "lackey_label", key = "ll", tool = "lackey", title = "lackey: this was", prefix = true, choose = true, desc = "label what you wrote" },
}

-- The which-key groups: the letter after the prefix, and the product it names.
M.groups = {
  { key = "s", name = "scry", tool = "scry" },
  { key = "c", name = "conjure", tool = "conjure" },
  { key = "b", name = "spellbook", tool = "spellbook" },
  { key = "l", name = "lackey", tool = "lackey" },
}

-- The default `keys` table of setup: the prefix and each name's key.
-- Example: { prefix = "<leader>m", ["do"] = "a", …, scry_why = "sw", … }.
function M.defaults()
  local keys = { prefix = "<leader>m" }
  for _, one in ipairs(M.table_of_keys) do keys[one.name] = one.key end
  return keys
end

local bound, skipped, unknown = {}, {}, {}

-- ---- talking to the servers ----

-- Send a request to CLIENT, the same way on Neovim 0.10 and 0.11.
local function ask(client, method, params, handler, buf)
  if vim.fn.has("nvim-0.11") == 1 then return client:request(method, params, handler, buf) end
  return client.request(method, params, handler, buf)
end

-- The LSP form of the diagnostics on row ROW of BUF, as a code-action request carries them.
local function lsp_diagnostics(buf, row)
  local out = {}
  for _, d in ipairs(vim.diagnostic.get(buf, { lnum = row })) do
    local lsp = d.user_data and d.user_data.lsp
    if lsp then table.insert(out, lsp) end
  end
  return out
end

-- Ask every client on BUF that offers code actions for those on row ROW (0-based), then call
-- DONE with { { client = client, action = action } } once all have answered. ONLY limits the
-- kinds (`{ "quickfix" }`), or nil for all.
function M.actions_on_row(buf, row, only, done)
  local clients = vim.tbl_filter(function(c) return c.server_capabilities and c.server_capabilities.codeActionProvider end,
    vim.lsp.get_clients({ bufnr = buf }))
  local found, waiting = {}, #clients
  if waiting == 0 then return done(found) end
  local params = {
    textDocument = { uri = vim.uri_from_bufnr(buf) },
    range = { start = { line = row, character = 0 }, ["end"] = { line = row, character = 0 } },
    context = { diagnostics = lsp_diagnostics(buf, row), triggerKind = 1, only = only },
  }
  for _, client in ipairs(clients) do
    ask(client, "textDocument/codeAction", params, function(_, actions)
      for _, action in ipairs(actions or {}) do table.insert(found, { client = client, action = action }) end
      waiting = waiting - 1
      if waiting == 0 then done(found) end
    end, buf)
  end
end

-- Run ACTION's command on CLIENT: sorcerer's actions are commands its server runs.
function M.run_command(client, action, buf, done)
  local command = type(action.command) == "table" and action.command or action
  ask(client, "workspace/executeCommand", { command = command.command, arguments = command.arguments },
    function(err, result) if done then done(err, result) end end, buf)
end

-- ---- what a key runs ----

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

-- Run the code action titled TITLE as code_action_titled does, but when the line offers none
-- say NONE instead of Neovim's "No code actions available", which reads as if the key were
-- broken. The tool's own server is asked first; without one the action runs as usual.
-- Example: `<leader>ma` on a comment lackey read as an aside says why there is no task.
local function code_action_titled_or_say(tool, title, prefix, choose, none)
  local client = tool and vim.lsp.get_clients({ bufnr = 0, name = tool })[1]
  if not client or not none then return code_action_titled(title, prefix, choose) end
  local params = vim.lsp.util.make_range_params(0, client.offset_encoding)
  params.context = { diagnostics = lsp_diagnostics(0, params.range.start.line), triggerKind = 1 }
  local buf = vim.api.nvim_get_current_buf()
  ask(client, "textDocument/codeAction", params, function(_, actions)
    for _, action in ipairs(actions or {}) do
      if action.title:sub(1, #title) == title then
        return vim.api.nvim_buf_call(buf, function() code_action_titled(title, prefix, choose) end)
      end
    end
    vim.notify(none, vim.log.levels.INFO)
  end, buf)
end

-- Whether ACTION is one of sorcerer's that fixes nothing: scry's, conjure's and lackey's actions
-- are quick fixes by kind, but none of them fixes the line.
local function not_a_fix(action)
  local title = action.title or ""
  return title:match("^scry: ") ~= nil or title:match("^conjure: ") ~= nil or title:match("^lackey: ") ~= nil
    or title == "Conjure here"
end

-- Fix this: the line's spellbook fix when it has one, else the line's preferred quick fix (any
-- server's), else the menu of its quick fixes (the one, applied, when there is one); with none
-- it says so.
-- Example: on a line ruff flags and spellbook does not, the key runs ruff's preferred fix.
local function fix_this()
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  M.actions_on_row(buf, row, { "quickfix" }, function(found)
    local fixes, preferred = 0, false
    for _, one in ipairs(found) do
      if require("sorcerer.spellbook").is_fix(one.action) then
        return vim.api.nvim_buf_call(buf, function() require("sorcerer.spellbook").fix_here() end)
      end
      if not not_a_fix(one.action) then
        fixes = fixes + 1
        preferred = preferred or one.action.isPreferred == true
      end
    end
    if fixes == 0 then return vim.notify("nothing to fix on this line", vim.log.levels.INFO) end
    vim.api.nvim_buf_call(buf, function()
      vim.lsp.buf.code_action({
        apply = true,
        context = { only = { "quickfix" } },
        filter = function(action) return not not_a_fix(action) and (not preferred or action.isPreferred == true) end,
      })
    end)
  end)
end

local runs = {
  fix_this = fix_this,
  undo_last = function() require("sorcerer.last_change").undo() end,
  review = function() require("sorcerer.scry").review_here() end,
  list_findings = function() require("sorcerer.scry").list_findings() end,
  spellbook_fix = function() require("sorcerer.spellbook").fix_here() end,
  check_file = function() require("sorcerer.spellbook").check_file() end,
}

-- What key ONE does when pressed.
local function run_of(one)
  if one.cmd then return function() vim.cmd(one.cmd) end end
  if one.run then return runs[one.run] end
  local tool = type(one.tool) == "string" and one.tool or nil
  return function() code_action_titled_or_say(tool, one.title, one.prefix, one.choose, one.none) end
end

-- ---- binding ----

-- Take back the maps this module made (only those still ours: a key you mapped since is left).
local function unbind_ours()
  for _, one in ipairs(bound) do
    for _, mode in ipairs(one.modes) do
      if vim.fn.maparg(one.lhs, mode, false, true).desc == one.desc then pcall(vim.keymap.del, mode, one.lhs) end
    end
  end
  bound, skipped, unknown = {}, {}, {}
end

local function taken(lhs, modes)
  for _, mode in ipairs(modes) do
    if vim.fn.maparg(lhs, mode) ~= "" then return true end
  end
  return false
end

-- Whether TOOL (a name, or a list of which any one will do) is on in OPTS.
local function on(opts, tool)
  for _, name in ipairs(type(tool) == "table" and tool or { tool }) do
    if (opts[name] or {}).enabled then return true end
  end
  return false
end

-- Name the prefix and each product's group for which-key, when it is installed: `<leader>m` is
-- "sorcerer", `<leader>ms` "scry", and so on for the tools that are on.
local function name_groups(opts, prefix)
  local ok, wk = pcall(require, "which-key")
  if not ok or type(wk) ~= "table" then return end
  local groups = { { prefix, group = "sorcerer" } }
  for _, g in ipairs(M.groups) do
    if on(opts, g.tool) then table.insert(groups, { prefix .. g.key, group = g.name }) end
  end
  if wk.add then return pcall(wk.add, groups) end
  if wk.register then
    local spec = {}
    for _, g in ipairs(groups) do spec[g[1]] = { name = g.group } end
    pcall(wk.register, spec)
  end
end

-- OPTS is the whole setup table: its `keys` (a table, or false for none) and which tools are on.
function M.setup(opts)
  unbind_ours()
  local keys = opts.keys
  if not keys then return end
  local prefix = keys.prefix or "<leader>m"
  local known = { prefix = true }
  for _, one in ipairs(M.table_of_keys) do
    known[one.name] = true
    local key = keys[one.name]
    if key and on(opts, one.tool) then
      local lhs = prefix .. key
      local modes = one.modes or { "n" }
      if taken(lhs, modes) then
        table.insert(skipped, { name = one.name, lhs = lhs })
      else
        vim.keymap.set(modes, lhs, run_of(one), { desc = one.desc })
        table.insert(bound, { name = one.name, lhs = lhs, modes = modes, desc = one.desc })
      end
    end
  end
  for name in pairs(keys) do
    if not known[name] then table.insert(unknown, name) end
  end
  table.sort(unknown)
  name_groups(opts, prefix)
end

-- The key bound to NAME ("next_step", "undo", …), as written (`<leader>mn`), or nil.
function M.lhs(name)
  for _, one in ipairs(bound) do
    if one.name == name then return one.lhs end
  end
end

-- The key that asks conjure for the next step: the common one, else conjure's own, or nil.
function M.conjure_lhs()
  return M.lhs("next_step") or M.lhs("conjure_next")
end

-- The keys not bound because the lhs was already mapped: { { name, lhs } }.
function M.skipped()
  return vim.deepcopy(skipped)
end

-- The names in `keys` that are no key of sorcerer's (an old name, a typo), sorted.
function M.unknown()
  return vim.deepcopy(unknown)
end

-- The keys bound: { { name, lhs } }.
function M.bound()
  return vim.tbl_map(function(one) return { name = one.name, lhs = one.lhs } end, bound)
end

return M
