-- The plan of a generation as a scratch float: each file with its status, then the text of each
-- new file, its holes lit. <CR> applies, q or <Esc> cancels. Nothing here talks to a server.
local M = {}

local ns = vim.api.nvim_create_namespace("sorcerer_spellbook_plan")

-- The float's lines, and the (0-based) lines to light as holes. PLAN is the server's reply.
function M.lines(plan)
  local lines, lit = {}, {}
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
      vim.list_extend(lines, vim.split(file.text, "\n", { plain = true, trimempty = true }))
      for _, hole in ipairs(plan.holes) do
        for _, place in ipairs(hole.places) do
          if hole.source == "placeholder" and place.file == file.path then lit[first + place.line - 1] = true end
        end
      end
    end
  end
  return lines, lit
end

-- Show PLAN in a float. ON_APPLY runs on <CR>; both keys close the float first.
function M.show(plan, on_apply)
  local lines, lit = M.lines(plan)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for line in pairs(lit) do
    vim.api.nvim_buf_set_extmark(buf, ns, line, 0, { line_hl_group = "DiagnosticInfo" })
  end
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
