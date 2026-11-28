-- The hole session after `:Spellbook new`: the written file's holes work like snippet
-- placeholders. The first placeholder is selected (select mode), typing replaces it, and
-- `<Tab>` / `<S-Tab>` move to the next / previous hole. Each hole is an extmark that grows with
-- what you type, so a hole stays a hole while you fill it. Holes in other files stay marked
-- (`]d` walks them) and the end line names them.
-- The keys are buffer-local, in insert and select mode only: normal-mode `<Tab>` (which is
-- `<C-i>`) and every global map are never touched, so a completion plugin's `<Tab>` is back the
-- moment the session ends. A buffer-local map you had on those keys is put back.
local M = {}

M.ns = vim.api.nvim_create_namespace("sorcerer_hole_session")

-- buffer -> { stops, ids, at, keys, conjure_lhs, saved, others, group }
local sessions = {}

-- Show TEXT on the message line, not kept in the message history.
function M.echo(text)
  vim.api.nvim_echo({ { text } }, false, {})
end

-- The byte column of UTF-16 column COL in LINE (clamped to the line).
-- Example: in `"é" + x`, UTF-16 column 5 is byte column 6.
local function byte_col(line, col)
  if vim.fn.has("nvim-0.11") == 1 then
    return vim.str_byteindex(line, "utf-16", col, false)
  end
  local ok, b = pcall(vim.str_byteindex, line, col, true)
  return ok and b or #line
end

-- STOP's span in BUF as byte positions { row, col, end_row, end_col }, 0-based. A range that
-- runs past its line (the server's whole-line fallback) spans the line's text after its indent.
local function span_of(buf, stop)
  local s, e = stop.range.start, stop.range["end"]
  local line = vim.api.nvim_buf_get_lines(buf, s.line, s.line + 1, false)[1] or ""
  if e.line > s.line then
    local indent = #(line:match("^%s*"))
    return { s.line, indent, s.line, #line }
  end
  return { s.line, byte_col(line, s.character), e.line, byte_col(line, e.character) }
end

-- Where stop I of SESSION is now: { row, col, end_row, end_col }, 0-based bytes.
local function where(buf, session, i)
  local m = vim.api.nvim_buf_get_extmark_by_id(buf, M.ns, session.ids[i], { details = true })
  return { m[1], m[2], m[3].end_row, m[3].end_col }
end

-- The message for hole I of N: what it wants and which keys move on. KEYS is the session's
-- `{ next, prev }`; CONJURE_LHS the conjure key, or nil when conjure is not here.
-- Example: `hole 1 of 3 · field: its first input · type to replace · <Tab> next · <leader>mn conjure`.
function M.message_text(i, n, stop, keys, conjure_lhs)
  local parts = {
    ("hole %d of %d"):format(i, n),
    ("%s: %s"):format(stop.name, stop.instruction),
    "type to replace",
    i == n and ("%s done"):format(keys.next) or ("%s next"):format(keys.next),
  }
  if conjure_lhs then table.insert(parts, ("%s conjure"):format(conjure_lhs)) end
  return table.concat(parts, " · ")
end

-- The line said when the session ends: done, and where the holes of other files are.
-- Example: OTHERS = { ["command__test.py"] = 1 } gives
-- `spellbook: holes done · 1 more in command__test.py, marked (]d)`.
function M.end_text(others)
  local names, n = {}, 0
  for name, count in pairs(others) do
    table.insert(names, name)
    n = n + count
  end
  if n == 0 then return "spellbook: holes done" end
  table.sort(names)
  return ("spellbook: holes done · %d more in %s, marked (]d)"):format(n, table.concat(names, ", "))
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "n", true)
end

-- Put the cursor on hole I: an empty hole starts insert there; else its placeholder is selected
-- in select mode, so typing replaces it (the key dance of Neovim's own vim/snippet.lua).
local function select(buf, i)
  local session = sessions[buf]
  session.at = i
  local r = where(buf, session, i)
  local mode = vim.fn.mode()
  local leave = mode ~= "n" and "<Esc>" or ""
  local say = ("<Cmd>lua require('sorcerer.spellbook_holes').say(%d)<CR>"):format(buf)
  if r[1] == r[3] and r[2] == r[4] then
    local line = vim.api.nvim_buf_get_lines(buf, r[1], r[1] + 1, false)[1] or ""
    local start = r[2] >= #line and "<Cmd>startinsert!<CR>" or "<Cmd>startinsert<CR>"
    feed(table.concat({ leave, ("<Cmd>call cursor(%d,%d)<CR>"):format(r[1] + 1, r[2] + 1), start, say }))
    return
  end
  local last = vim.o.selection == "exclusive" and r[4] + 1 or r[4]
  feed(table.concat({
    leave,
    ("<Cmd>call cursor(%d,%d)<CR>"):format(r[1] + 1, r[2] + 1),
    "v",
    ("<Cmd>call cursor(%d,%d)<CR>"):format(r[3] + 1, last),
    -- the replaced placeholder goes to the black hole register (Neovim 0.11+), not `""`
    vim.fn.has("nvim-0.11") == 1 and "o<C-g><C-r>_" or "o<C-g>",
    say,
  }))
end

-- Show the message of the hole the session of BUF is on.
function M.say(buf)
  local session = sessions[buf]
  if not session then return end
  local i = session.at
  M.echo(M.message_text(i, #session.stops, session.stops[i], session.keys, session.conjure_lhs))
end

-- End the session of BUF: its keys taken back (yours restored), its extmarks cleared, the end
-- line said. Ending twice is harmless.
function M.stop(buf)
  local session = sessions[buf]
  if not session then return end
  sessions[buf] = nil
  pcall(vim.api.nvim_del_augroup_by_id, session.group)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
    pcall(vim.api.nvim_buf_call, buf, function()
      for _, lhs in ipairs({ session.keys.next, session.keys.prev }) do
        for _, mode in ipairs({ "i", "s" }) do pcall(vim.keymap.del, mode, lhs, { buffer = buf }) end
      end
      for _, s in ipairs(session.saved) do vim.fn.mapset(s.mode, false, s.map) end
    end)
  end
  vim.notify(M.end_text(session.others))
end

-- Move by STEP (1 or -1) through the session of BUF; past the last hole ends it.
local function move(buf, step)
  local session = sessions[buf]
  if not session then return end
  local i = session.at + step
  if i > #session.stops then
    if vim.fn.mode() == "s" then feed("<Esc>") end
    return M.stop(buf)
  end
  select(buf, math.max(i, 1))
end

-- Is a hole session running in BUF?
function M.active(buf)
  return sessions[buf] ~= nil
end

-- Start a session on BUF (the current buffer) over STOPS, the apply reply's stops in this file
-- (`{ name, instruction, range = { start, ["end"] } }`, UTF-16 ranges). KEYS is `{ next, prev }`;
-- CONJURE_LHS the conjure key when conjure is here; OTHERS counts the holes of other files by
-- file name. Selects the first hole.
function M.start(buf, stops, keys, conjure_lhs, others)
  M.stop(buf)
  local session = { stops = stops, ids = {}, at = 1, keys = keys, conjure_lhs = conjure_lhs, saved = {}, others = others or {} }
  for _, stop in ipairs(stops) do
    local r = span_of(buf, stop)
    table.insert(session.ids, vim.api.nvim_buf_set_extmark(buf, M.ns, r[1], r[2], {
      end_row = r[3], end_col = r[4],
      right_gravity = false, end_right_gravity = true,
      hl_group = "SorcererHolePlaceholder",
    }))
  end
  for _, lhs in ipairs({ keys.next, keys.prev }) do
    for _, mode in ipairs({ "i", "s" }) do
      local map = vim.fn.maparg(lhs, mode, false, true)
      if map.buffer == 1 then table.insert(session.saved, { mode = mode, map = map }) end
    end
  end
  vim.keymap.set({ "i", "s" }, keys.next, function() move(buf, 1) end, { buffer = buf, desc = "spellbook: next hole" })
  vim.keymap.set({ "i", "s" }, keys.prev, function() move(buf, -1) end, { buffer = buf, desc = "spellbook: previous hole" })
  session.group = vim.api.nvim_create_augroup("sorcerer_hole_session_" .. buf, { clear = true })
  vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
    group = session.group, buffer = buf, callback = function() M.stop(buf) end,
  })
  sessions[buf] = session
  select(buf, 1)
end

return M
