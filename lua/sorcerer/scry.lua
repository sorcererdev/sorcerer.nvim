-- scry's language server: `scry lsp` starts on the files that open, one client a project
-- root (Neovim reuses a client with the same name and root). The root is the nearest
-- `.sorcerer/` upward, else the nearest `.git`, the server's own order. No filetype list:
-- scry decides what it reviews.
local M = {}

local opts = nil
-- the work scry reports: token -> message, and the token that spoke last
local work, latest = {}, nil

-- The project root of buffer BUF, or nil.
function M.root(buf)
  return vim.fs.root(buf, ".sorcerer") or vim.fs.root(buf, ".git")
end

function M.attach(buf)
  if not opts or not opts.enabled then return end
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then return end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or not vim.uv.fs_stat(name) then return end
  local root = M.root(buf)
  if not root then return end
  vim.lsp.start(
    vim.tbl_extend("error", { name = "scry", cmd = opts.cmd, root_dir = root }, require("sorcerer.working").client_config()),
    { bufnr = buf }
  )
end

-- "scry: <message>" while scry reports a review, else "".
function M.status()
  local message = latest and work[latest]
  return message and ("scry: " .. message) or ""
end

local function follow_progress(ev)
  local client = vim.lsp.get_client_by_id(ev.data.client_id)
  if not client or client.name ~= "scry" then return end
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

-- OPTS is the `scry` table of setup.
function M.setup(o)
  opts = o
  work, latest = {}, nil
  local group = vim.api.nvim_create_augroup("sorcerer_scry", { clear = true })
  vim.api.nvim_create_autocmd("LspProgress", { group = group, callback = follow_progress })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufWritePost" }, {
    group = group,
    callback = function(a) M.attach(a.buf) end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then M.attach(buf) end
  end
end

return M
