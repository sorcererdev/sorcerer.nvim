-- conjure's language server: `conjure lsp`, the sorcerer suite's writer. It lands a change
-- through `workspace/applyEdit` and marks every file it changed, so two things are asked of
-- this client (the server cannot do them for itself):
--   * `debounce_text_changes = 0`: Neovim sends `didChange` at once, not up to 150 ms late, so
--     the server sees what you type while a change is conjured and keeps its edit from landing
--     over it;
--   * conjure is attached to every buffer under the project root: a file the edit opens (one
--     you had not opened) would otherwise be a buffer the server cannot see, and a change in it
--     counts as not landed.
-- One client a project root (Neovim reuses a client with the same name and root). The root is
-- the nearest `.sorcerer/` upward, else the nearest `.git`, the server's own order.
local M = {}

local opts = nil
-- the work conjure reports: token -> message, and the token that spoke last
local work, latest = {}, nil

-- The project root of buffer BUF, or nil.
function M.root(buf)
  return vim.fs.root(buf, ".sorcerer") or vim.fs.root(buf, ".git")
end

-- Attach conjure to buffer BUF when conjure is enabled and BUF is a file under a project root.
function M.attach(buf)
  if not opts or not opts.enabled then return end
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then return end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or not vim.uv.fs_stat(name) then return end
  local root = M.root(buf)
  if not root then return end
  if not require("sorcerer.program").runnable("conjure", opts.cmd) then return end
  vim.lsp.start(
    vim.tbl_extend("error", {
      name = "conjure",
      cmd = opts.cmd,
      root_dir = root,
      flags = { debounce_text_changes = 0 },
    }, require("sorcerer.working").client_config()),
    { bufnr = buf }
  )
end

-- "conjure: <message>" while conjure works on a change, else "".
function M.status()
  local message = latest and work[latest]
  return message and ("conjure: " .. message) or ""
end

local function follow_progress(ev)
  local client = vim.lsp.get_client_by_id(ev.data.client_id)
  if not client or client.name ~= "conjure" then return end
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

-- OPTS is the `conjure` table of setup.
function M.setup(o)
  opts = o
  work, latest = {}, nil
  require("sorcerer.program").forget()
  local group = vim.api.nvim_create_augroup("sorcerer_conjure", { clear = true })
  vim.api.nvim_create_autocmd("LspProgress", { group = group, callback = follow_progress })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufWritePost", "BufEnter" }, {
    group = group,
    callback = function(a) M.attach(a.buf) end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then M.attach(buf) end
  end
end

return M
