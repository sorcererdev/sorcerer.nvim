-- What a server is working on, drawn where it works: while scry reviews, conjure writes or
-- apprentice researches a question or runs a task, a grey `⟳ scry: reviewing…` sits at the end
-- of the line being worked on, and is gone when the work ends. The servers know the lines; they
-- send them in the notification `sorcerer/working` (`{ units = { { uri, line, text } } }`, an
-- empty list when done) to a client that says in its init_options that it draws them. An
-- extmark follows its line as you edit.
--
-- The `⟳` spins (⠋⠙⠹…) while anything is drawn: one timer for every client's marks, started by
-- the first mark and stopped when the last goes. Each tick rewrites only the marks in buffers a
-- window shows; a hidden buffer's mark keeps its frame until it is shown. `working = { animate =
-- false }` in setup keeps the `⟳` still.
local M = {}

M.ns = vim.api.nvim_create_namespace("sorcerer_working")
M.frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
M.interval = 90

-- the marks each client drew: client id -> { { buf, id, text } }, text without its glyph
local drawn = {}
local animate = true
local timer, frame = nil, 1

function M.set_highlights()
  vim.api.nvim_set_hl(0, "SorcererWorking", { link = "Comment", default = true })
end

-- `⟳ apprentice: researching…` with the spinning frame in place of the `⟳`; text without a
-- leading `⟳` is drawn as sent.
local function with_frame(text)
  local rest = text:match("^⟳%s*(.*)$")
  if not rest or not animate then return text end
  return M.frames[frame] .. " " .. rest
end

local function any_drawn()
  for _, marks in pairs(drawn) do
    if #marks > 0 then return true end
  end
  return false
end

-- One tick: the next frame on every mark in a shown buffer, in place (same extmark id).
local function tick()
  frame = frame % #M.frames + 1
  for _, marks in pairs(drawn) do
    for _, mark in ipairs(marks) do
      local buf, id, text = mark[1], mark[2], mark[3]
      if vim.api.nvim_buf_is_valid(buf) and vim.fn.bufwinid(buf) ~= -1 then
        local at = vim.api.nvim_buf_get_extmark_by_id(buf, M.ns, id, {})
        if at[1] then
          pcall(vim.api.nvim_buf_set_extmark, buf, M.ns, at[1], 0, {
            id = id,
            virt_text = { { with_frame(text), "SorcererWorking" } },
            virt_text_pos = "eol",
          })
        end
      end
    end
  end
end

local function stop_timer()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

-- The timer runs exactly while something is drawn and animation is on.
local function keep_timer()
  if not animate or not any_drawn() then return stop_timer() end
  if timer then return end
  frame = 1
  timer = vim.uv.new_timer()
  timer:start(M.interval, M.interval, vim.schedule_wrap(function()
    if timer then tick() end
  end))
end

-- Whether the spinning timer runs (for the specs).
function M.animating()
  return timer ~= nil
end

-- Takes away what client CLIENT_ID drew.
function M.clear(client_id)
  for _, mark in ipairs(drawn[client_id] or {}) do
    if vim.api.nvim_buf_is_valid(mark[1]) then pcall(vim.api.nvim_buf_del_extmark, mark[1], M.ns, mark[2]) end
  end
  drawn[client_id] = nil
  keep_timer()
end

-- Draws UNITS for client CLIENT_ID in place of what it drew before. A unit in a file with no
-- loaded buffer, or past the buffer's last line, is left out (no buffer is opened for it).
function M.show(client_id, units)
  for _, mark in ipairs(drawn[client_id] or {}) do
    if vim.api.nvim_buf_is_valid(mark[1]) then pcall(vim.api.nvim_buf_del_extmark, mark[1], M.ns, mark[2]) end
  end
  local marks = {}
  for _, unit in ipairs(units or {}) do
    local buf = vim.fn.bufnr(vim.uri_to_fname(unit.uri))
    if buf > 0 and vim.api.nvim_buf_is_loaded(buf) and unit.line < vim.api.nvim_buf_line_count(buf) then
      local id = vim.api.nvim_buf_set_extmark(buf, M.ns, unit.line, 0, {
        virt_text = { { with_frame(unit.text), "SorcererWorking" } },
        virt_text_pos = "eol",
      })
      table.insert(marks, { buf, id, unit.text })
    end
  end
  drawn[client_id] = marks
  keep_timer()
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

-- OPTS is the `working` table of setup: `animate` (default true) spins the `⟳`.
function M.setup(opts)
  animate = not (opts and opts.animate == false)
  keep_timer()
  M.set_highlights()
  local group = vim.api.nvim_create_augroup("sorcerer_working", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = M.set_highlights })
end

return M
