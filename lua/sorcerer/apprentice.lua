-- apprentice's language server: `apprentice lsp`, a coding agent whose whole interface is the
-- editor (a prototype). It answers and checks what you write, offers what you ask for, and runs
-- a task in your buffers when you accept: every change lands through `workspace/applyEdit`,
-- undoable. Like conjure it needs, from this client:
--   * `debounce_text_changes = 0`: Neovim sends `didChange` at once, so a task's write never
--     lands over what you typed a moment ago, and your edits reach the agent after its next tool;
--   * apprentice attached to every buffer under the project root (a file a task opens included).
-- It draws three notifications the server sends only to a client that lists them in
-- `init_options.handles`:
--   * `sorcerer/ghost` { uri, line (from 0), lines }: grey lines below `line` (`virt_lines`),
--     gone at your next edit of that line, or when `lines` is empty;
--   * `sorcerer/note` { uri }: a note opened in a vertical split beside the code: the agent's,
--     or a long answer when you ask for it (`<leader>mo`); an answer never opens one unasked;
--   * `sorcerer/showDiff` { uri, before, title }: the file before the task against now, a
--     scratch buffer and the live one side by side in diff mode, in a tab of their own.
-- Everything else (marks, code actions, the picker, edits) is Neovim's own.
local M = {}

M.ghost_ns = vim.api.nvim_create_namespace("sorcerer_ghost")
M.handled = { "sorcerer/ghost", "sorcerer/note", "sorcerer/showDiff" }

local opts = nil
-- the work apprentice reports: token -> message, and the token that spoke last
local work, latest = {}, nil
-- the ghosts drawn: buf -> { [line] = extmark id }
local ghosts = {}

function M.root(buf)
  return vim.fs.root(buf, ".sorcerer") or vim.fs.root(buf, ".git")
end

-- The client config apprentice adds to sorcerer/working's: the notifications it handles.
function M.client_config()
  local config = require("sorcerer.working").client_config()
  config.init_options.handles = vim.deepcopy(M.handled)
  -- the key that opens a long answer, so its mark can say it (`<leader>mo opens the whole answer`)
  config.init_options.keys = { openAnswer = require("sorcerer.keys").lhs("open_answer") }
  config.handlers["sorcerer/ghost"] = function(_, result) M.ghost(result) end
  config.handlers["sorcerer/note"] = function(_, result) M.note(result) end
  config.handlers["sorcerer/showDiff"] = function(_, result) M.show_diff(result) end
  return config
end

-- Attach apprentice to buffer BUF when it is enabled and BUF names a file (on disk or not yet,
-- but no other scheme) under a project root.
function M.attach(buf)
  if not opts or not opts.enabled then return end
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then return end
  local name = vim.api.nvim_buf_get_name(buf)
  -- a file need not be on disk yet: a file apprentice's edit creates is only a buffer in Neovim
  -- (CreateFile with ignoreIfExists writes nothing), and apprentice must see it to check it landed
  if name == "" or name:match("^%a[%w+.-]*://") then return end
  local root = M.root(buf)
  if not root then return end
  if not require("sorcerer.program").runnable("apprentice", opts.cmd) then return end
  vim.lsp.start(
    vim.tbl_extend("error", {
      name = "apprentice",
      cmd = opts.cmd,
      root_dir = root,
      flags = { debounce_text_changes = 0 },
    }, M.client_config()),
    { bufnr = buf }
  )
end

local function loaded_buffer(uri)
  local buf = vim.fn.bufnr(vim.uri_to_fname(uri))
  if buf > 0 and vim.api.nvim_buf_is_loaded(buf) then return buf end
end

-- Grey lines under a line, not in the buffer; an empty list takes them away.
function M.ghost(result)
  if not result or not result.uri then return end
  local buf = loaded_buffer(result.uri)
  if not buf then return end
  ghosts[buf] = ghosts[buf] or {}
  local line = result.line or 0
  local old = ghosts[buf][line]
  if old then pcall(vim.api.nvim_buf_del_extmark, buf, M.ghost_ns, old) end
  ghosts[buf][line] = nil
  local lines = result.lines or {}
  if #lines == 0 or line >= vim.api.nvim_buf_line_count(buf) then return end
  local virt = {}
  for _, text in ipairs(lines) do table.insert(virt, { { text, "SorcererGhost" } }) end
  ghosts[buf][line] = vim.api.nvim_buf_set_extmark(buf, M.ghost_ns, line, 0, { virt_lines = virt })
end

-- Your edit of a line with a ghost under it takes the ghost away. The line is the cursor's in
-- the window showing the buffer, which need not be the current window; a buffer no window
-- shows keeps its ghosts.
local function clear_edited_ghost(buf)
  local marks = ghosts[buf]
  if not marks then return end
  local win = vim.fn.bufwinid(buf)
  if win == -1 then return end
  local cursor = vim.api.nvim_win_get_cursor(win)[1] - 1
  local id = marks[cursor]
  if id then
    pcall(vim.api.nvim_buf_del_extmark, buf, M.ghost_ns, id)
    marks[cursor] = nil
  end
end

-- The agent's note, in a vertical split beside the code; the cursor stays where it was.
function M.note(result)
  if not result or not result.uri then return end
  local back = vim.api.nvim_get_current_win()
  vim.cmd("vsplit " .. vim.fn.fnameescape(vim.uri_to_fname(result.uri)))
  if vim.api.nvim_win_is_valid(back) then vim.api.nvim_set_current_win(back) end
end

-- The file before the task against the live buffer, in diff mode, side by side.
function M.show_diff(result)
  if not result or not result.uri then return end
  -- in a tab of its own (`:tabclose` ends it), so the window you were in, unsaved or not, stays
  local buf = vim.fn.bufadd(vim.uri_to_fname(result.uri))
  vim.fn.bufload(buf)
  vim.bo[buf].buflisted = true
  vim.cmd("tab sbuffer " .. buf)
  local live = vim.api.nvim_get_current_win()
  local filetype = vim.bo.filetype
  vim.cmd("leftabove vnew")
  local scratch = vim.api.nvim_get_current_buf()
  vim.bo[scratch].buftype = "nofile"
  vim.bo[scratch].bufhidden = "wipe"
  vim.bo[scratch].swapfile = false
  local before = vim.split(result.before or "", "\n", { plain = true })
  if before[#before] == "" then table.remove(before) end
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, before)
  vim.bo[scratch].modifiable = false
  vim.bo[scratch].filetype = filetype
  pcall(vim.api.nvim_buf_set_name, scratch, result.title or "apprentice: before")
  vim.cmd("diffthis")
  vim.api.nvim_set_current_win(live)
  vim.cmd("diffthis")
end

-- "apprentice: <message>" while a task runs, else "".
function M.status()
  local message = latest and work[latest]
  return message and ("apprentice: " .. message) or ""
end

local function follow_progress(ev)
  local client = vim.lsp.get_client_by_id(ev.data.client_id)
  if not client or client.name ~= "apprentice" then return end
  local params = ev.data.params or {}
  local value, token = params.value or {}, tostring(params.token)
  if value.kind == "end" then
    work[token] = nil
    if latest == token then latest = next(work) end
  elseif type(value.message) == "string" then
    work[token] = value.message
    latest = token
  end
end

function M.set_highlights()
  vim.api.nvim_set_hl(0, "SorcererGhost", { link = "Comment", default = true })
end

-- OPTS is the `apprentice` table of setup.
function M.setup(o)
  opts = o
  work, latest, ghosts = {}, nil, {}
  M.set_highlights()
  local group = vim.api.nvim_create_augroup("sorcerer_apprentice", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = M.set_highlights })
  vim.api.nvim_create_autocmd("LspProgress", { group = group, callback = follow_progress })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function(a) clear_edited_ghost(a.buf) end,
  })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufWritePost", "BufEnter" }, {
    group = group,
    callback = function(a) M.attach(a.buf) end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then M.attach(buf) end
  end
end

return M
