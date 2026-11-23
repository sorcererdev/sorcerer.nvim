-- What a server is working on, drawn where it works: while scry reviews or conjure writes, a
-- grey `⟳ scry: reviewing…` sits at the end of the first line of each unit being worked on,
-- and is gone when the work ends. The servers know the units; they send them in the
-- notification `sorcerer/working` (`{ units = { { uri, line, text } } }`, an empty list when
-- done) to a client that says in its init_options that it draws them. An extmark follows its
-- line as you edit.
local M = {}

M.ns = vim.api.nvim_create_namespace("sorcerer_working")

-- the extmarks each client drew: client id -> { { buf, id } }
local drawn = {}

function M.set_highlights()
  vim.api.nvim_set_hl(0, "SorcererWorking", { link = "Comment", default = true })
end

-- Takes away what client CLIENT_ID drew.
function M.clear(client_id)
  for _, mark in ipairs(drawn[client_id] or {}) do
    if vim.api.nvim_buf_is_valid(mark[1]) then pcall(vim.api.nvim_buf_del_extmark, mark[1], M.ns, mark[2]) end
  end
  drawn[client_id] = nil
end

-- Draws UNITS for client CLIENT_ID in place of what it drew before. A unit in a file with no
-- loaded buffer, or past the buffer's last line, is left out (no buffer is opened for it).
function M.show(client_id, units)
  M.clear(client_id)
  local marks = {}
  for _, unit in ipairs(units or {}) do
    local buf = vim.fn.bufnr(vim.uri_to_fname(unit.uri))
    if buf > 0 and vim.api.nvim_buf_is_loaded(buf) and unit.line < vim.api.nvim_buf_line_count(buf) then
      local id = vim.api.nvim_buf_set_extmark(buf, M.ns, unit.line, 0, {
        virt_text = { { unit.text, "SorcererWorking" } },
        virt_text_pos = "eol",
      })
      table.insert(marks, { buf, id })
    end
  end
  drawn[client_id] = marks
end

-- The part of a client's config that makes it draw: the init option that tells the server
-- (and no other server) to send, the handler for what it sends, and the clean-up when the server
-- exits with work in progress.
function M.client_config()
  return {
    init_options = { drawsWorking = true },
    handlers = {
      ["sorcerer/working"] = function(_, result, ctx) M.show(ctx.client_id, result and result.units) end,
    },
    on_exit = function(_, _, client_id) vim.schedule(function() M.clear(client_id) end) end,
  }
end

function M.setup()
  M.set_highlights()
  local group = vim.api.nvim_create_augroup("sorcerer_working", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = M.set_highlights })
end

return M
