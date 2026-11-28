-- The changes sorcerer's writers made, so `<leader>mu` (undo the last change) undoes the most
-- recent one whichever tool made it. conjure, lackey and spellbook all land their changes
-- through `workspace/applyEdit`; Neovim's handler for it is wrapped once, and every edit one of
-- them lands is remembered: the tool, the buffers it touched (with the row of its first change
-- and the buffer's `changedtick` right after) — the latest last.
--
-- Undoing asks the tool that made the change to take it back:
--   * conjure: the `conjure: Undo` action of conjure's mark (`✦`) nearest the change;
--   * lackey: the `lackey: Undo this task` action of the task's mark nearest the change;
--   * spellbook: Neovim's own undo in each buffer it changed (spellbook lands a plan as one
--     undo step a file), only while that change is still the buffer's last.
-- It says which tool's change it undoes. The edits a tool lands while it undoes are not
-- remembered as changes of their own.
local M = {}

local writers = { conjure = true, lackey = true, spellbook = true }
-- the changes, oldest first: { tool, at = { { buf, row, tick } }, when }
local changes = {}
-- tool -> time (vim.uv.now) until which its edits are its own undo, not a change
local undoing = {}
local MAX = 20
-- how long after an undo starts the tool's edits are counted as that undo
local UNDO_WINDOW_MS = 5000

-- The buffers and first rows of a WorkspaceEdit: { { buf, row } }, a file once.
local function places(edit)
  local rows, order = {}, {}
  local function note(uri, row)
    if not uri then return end
    if rows[uri] == nil then table.insert(order, uri) end
    if rows[uri] == nil or row < rows[uri] then rows[uri] = row end
  end
  for uri, edits in pairs(edit.changes or {}) do
    for _, e in ipairs(edits) do note(uri, e.range.start.line) end
  end
  for _, change in ipairs(edit.documentChanges or {}) do
    if change.textDocument then
      for _, e in ipairs(change.edits or {}) do note(change.textDocument.uri, e.range.start.line) end
    elseif change.kind == "create" then
      note(change.uri, 0)
    end
  end
  local out = {}
  for _, uri in ipairs(order) do
    local buf = vim.uri_to_bufnr(uri)
    table.insert(out, { buf = buf, row = rows[uri] })
  end
  return out
end

-- Remember that TOOL landed EDIT (a WorkspaceEdit), unless the tool is undoing. A lackey task
-- lands many edits: back-to-back edits of lackey's are one change.
function M.record(tool, edit)
  if not writers[tool] or type(edit) ~= "table" then return end
  if undoing[tool] and vim.uv.now() < undoing[tool] then
    undoing[tool] = vim.uv.now() + UNDO_WINDOW_MS
    return
  end
  local at = places(edit)
  for _, place in ipairs(at) do
    place.tick = vim.api.nvim_buf_is_valid(place.buf) and vim.api.nvim_buf_get_changedtick(place.buf) or 0
  end
  if #at == 0 then return end
  local last = changes[#changes]
  if tool == "lackey" and last and last.tool == "lackey" then
    for _, place in ipairs(at) do table.insert(last.at, place) end
    return
  end
  table.insert(changes, { tool = tool, at = at })
  if #changes > MAX then table.remove(changes, 1) end
end

-- The latest change: { tool, at }, or nil.
function M.last()
  return changes[#changes] and vim.deepcopy(changes[#changes])
end

function M.forget()
  changes, undoing = {}, {}
end

-- "a.py:12": where a change starts, for what is said.
local function where(place)
  local name = vim.api.nvim_buf_is_valid(place.buf) and vim.fs.basename(vim.api.nvim_buf_get_name(place.buf)) or "?"
  return ("%s:%d"):format(name, place.row + 1)
end

-- The mark of TOOL's change nearest the change's latest place: { buf, row }, or nil. A conjure
-- mark is its diagnostic of code `change`; a lackey task's mark (`✦ lackey changed this line in
-- task …`) is its diagnostic of code `task`.
local function nearest_mark(tool, change)
  local function is_mark(d)
    return d.source == tool and d.code == (tool == "conjure" and "change" or "task")
  end
  -- the latest place first: a lackey task's edits are one change, and its mark is near the last
  for i = #change.at, 1, -1 do
    local place = change.at[i]
    if vim.api.nvim_buf_is_valid(place.buf) then
      local best
      for _, d in ipairs(vim.diagnostic.get(place.buf)) do
        if is_mark(d) and (not best or math.abs(d.lnum - place.row) < math.abs(best - place.row)) then best = d.lnum end
      end
      if best then return { buf = place.buf, row = best } end
    end
  end
end

-- Undo CHANGE through its tool's server: the action titled TITLE on its nearest mark.
local function undo_by_action(change, title, none)
  local mark = nearest_mark(change.tool, change)
  if not mark then return vim.notify(none, vim.log.levels.INFO) end
  local keys = require("sorcerer.keys")
  keys.actions_on_row(mark.buf, mark.row, nil, function(found)
    for _, one in ipairs(found) do
      if one.client.name == change.tool and one.action.title == title then
        table.remove(changes)
        undoing[change.tool] = vim.uv.now() + UNDO_WINDOW_MS
        vim.notify(("undo: %s's last change (%s)"):format(change.tool, where(mark)), vim.log.levels.INFO)
        return keys.run_command(one.client, one.action, mark.buf)
      end
    end
    vim.notify(none, vim.log.levels.INFO)
  end)
end

-- Undo a spellbook change: Neovim's undo in each buffer it changed, while the change is still
-- that buffer's last edit.
local function undo_in_buffers(change)
  local moved = vim.tbl_filter(function(place)
    return not vim.api.nvim_buf_is_valid(place.buf) or vim.api.nvim_buf_get_changedtick(place.buf) ~= place.tick
  end, change.at)
  if #moved > 0 then
    return vim.notify(("spellbook's last change is no longer the last edit of %s: undo it there with u"):format(where(moved[1])),
      vim.log.levels.WARN)
  end
  table.remove(changes)
  for _, place in ipairs(change.at) do
    vim.api.nvim_buf_call(place.buf, function() vim.cmd("silent undo") end)
  end
  vim.notify(("undo: spellbook's last change (%s)"):format(table.concat(vim.tbl_map(where, change.at), ", ")), vim.log.levels.INFO)
end

-- `<leader>mu`: undo the latest change conjure, lackey or spellbook made, and say whose.
function M.undo()
  local change = changes[#changes]
  if not change then
    return vim.notify("nothing to undo: conjure, lackey and spellbook have changed nothing yet", vim.log.levels.INFO)
  end
  if change.tool == "conjure" then
    return undo_by_action(change, "conjure: Undo", "conjure's last change can no longer be undone (its mark is gone)")
  end
  if change.tool == "lackey" then
    local running = require("sorcerer.lackey").status() ~= ""
    return undo_by_action(change, "lackey: Undo this task",
      running and ("lackey's task is still running: stop it first (%s)"):format(require("sorcerer.keys").lhs("stop") or "lackey: Stop this task")
        or "lackey's last task can no longer be undone (its mark is gone)")
  end
  undo_in_buffers(change)
end

-- Wrap Neovim's `workspace/applyEdit` handler once, so every edit a writer lands is remembered.
function M.setup()
  if M.wrapped then return end
  local original = vim.lsp.handlers["workspace/applyEdit"]
  if not original then return end
  M.wrapped = true
  vim.lsp.handlers["workspace/applyEdit"] = function(err, result, ctx, config)
    local reply = original(err, result, ctx, config)
    local client = ctx and vim.lsp.get_client_by_id(ctx.client_id)
    if client and result and (reply == nil or reply.applied ~= false) then M.record(client.name, result.edit) end
    return reply
  end
end

return M
