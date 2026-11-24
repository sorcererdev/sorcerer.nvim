-- The plan of a generation as a scratch float: each file with its status, then the text of each
-- new file, its holes lit. <CR> applies, q or <Esc> cancels. Nothing here talks to a server.
local M = {}

local ns = vim.api.nvim_create_namespace("sorcerer_spellbook_plan")

-- The float's lines; the (0-based) lines to light as holes, each with the placeholder's text
-- (or "" when the server did not say); and the sections: each new file's `{ path, first_row
-- (0-based row of its first line), text }`. PLAN is the server's reply.
function M.lines(plan)
  local lines, lit, sections = {}, {}, {}
  for _, file in ipairs(plan.files) do
    if file.status == "skipped" then
      table.insert(lines, ("= %s (exists, skipped)"):format(file.path))
    else
      table.insert(lines, ("+ %s (%d lines)"):format(file.path, file.lines))
    end
  end
  local placeholders = 0
  for _, hole in ipairs(plan.holes) do
    if hole.source == "placeholder" then placeholders = placeholders + 1 end
  end
  table.insert(lines, ("%d %s to fill"):format(placeholders, placeholders == 1 and "hole" or "holes"))
  for _, file in ipairs(plan.files) do
    if file.status == "new" then
      table.insert(lines, "")
      table.insert(lines, ("── %s ──"):format(file.path))
      local first = #lines
      local body = vim.split(file.text, "\n", { plain = true, trimempty = true })
      vim.list_extend(lines, body)
      table.insert(sections, { path = file.path, first_row = first, text = table.concat(body, "\n") })
      for _, hole in ipairs(plan.holes) do
        for _, place in ipairs(hole.places) do
          if hole.source == "placeholder" and place.file == file.path then lit[first + place.line - 1] = place.text or "" end
        end
      end
    end
  end
  return lines, lit, sections
end

-- Colour each section of BUF as its file's language: the tree-sitter `highlights` captures of a
-- parser over the section's text, as `@capture.lang` extmarks (so a colour scheme's own groups
-- apply). A file with no filetype, parser or highlights query is left plain, silently.
-- Example: a section for `a.lua` gets `@keyword.lua` on its `local`; a `.nolang` one nothing.
function M.highlight(buf, sections)
  for _, section in ipairs(sections) do
    local ft = vim.filetype.match({ filename = section.path })
    local lang = ft and vim.treesitter.language.get_lang(ft)
    local ok, parser = false, nil
    if lang then ok, parser = pcall(vim.treesitter.get_string_parser, section.text, lang) end
    local query = ok and vim.treesitter.query.get(lang, "highlights")
    if ok and query then
      local tree = parser:parse()[1]
      for id, node in query:iter_captures(tree:root(), section.text) do
        local name = query.captures[id]
        if name:sub(1, 1) ~= "_" then
          local sr, sc, er, ec = node:range()
          pcall(vim.api.nvim_buf_set_extmark, buf, ns, section.first_row + sr, sc, {
            end_row = section.first_row + er,
            end_col = ec,
            hl_group = "@" .. name .. "." .. lang,
            priority = 100,
          })
        end
      end
    end
  end
end

-- Light the placeholder PLACE_TEXT on row ROW of BUF (the whole line when its text is unknown).
local function light_hole(buf, row, place_text)
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local from, to = line:find(place_text, 1, true)
  if place_text == "" or not from then
    from = (line:find("%S") or 1)
    to = #line
  end
  vim.api.nvim_buf_set_extmark(buf, ns, row, from - 1, { end_row = row, end_col = to, hl_group = "SorcererHolePlaceholder", priority = 150 })
end

-- Show PLAN in a float. ON_APPLY runs on <CR>; both keys close the float first.
function M.show(plan, on_apply)
  local lines, lit, sections = M.lines(plan)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  M.highlight(buf, sections)
  for row, place_text in pairs(lit) do light_hole(buf, row, place_text) end
  vim.bo[buf].modifiable = false
  local width = math.min(100, math.max(40, vim.o.columns - 6))
  local height = math.max(3, math.min(#lines, vim.o.lines - 6))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = (" spellbook: %s · <CR> apply · q cancel "):format(plan.generator),
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
  })
  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  vim.keymap.set("n", "<CR>", function()
    close()
    on_apply()
  end, { buffer = buf, nowait = true })
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, close, { buffer = buf, nowait = true })
  end
  return buf
end

return M
