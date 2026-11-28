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
  if not require("sorcerer.program").runnable("scry", opts.cmd) then return end
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

-- Review the current file now. A buffer with unsaved changes is saved, which is what makes scry
-- review it; a saved one is sent to scry's `scry.review` command. scry reviews what changed in
-- the file since its last review, as on a save.
function M.review_here()
  local buf = vim.api.nvim_get_current_buf()
  local client = vim.lsp.get_clients({ bufnr = buf, name = "scry" })[1]
  if not client then return vim.notify("scry is not running on this file", vim.log.levels.WARN) end
  if vim.bo[buf].modified then return vim.cmd("update") end
  local command = { command = "scry.review", arguments = { vim.uri_from_bufnr(buf) } }
  local function said(err)
    if err then vim.notify("scry: " .. tostring(err.message or err), vim.log.levels.WARN) end
  end
  if vim.fn.has("nvim-0.11") == 1 then
    client:request("workspace/executeCommand", command, said, buf)
  else
    client.request("workspace/executeCommand", command, said, buf)
  end
end

-- The quickfix list of scry's findings in the open files (scry shows findings only in open
-- files), opened when there are any; with none it says so.
function M.list_findings()
  local findings = vim.tbl_filter(function(d) return d.source == "scry" end, vim.diagnostic.get(nil))
  if #findings == 0 then return vim.notify("scry: no findings in the open files", vim.log.levels.INFO) end
  vim.fn.setqflist({}, " ", { title = "scry findings", items = vim.diagnostic.toqflist(findings) })
  vim.cmd("copen")
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
  require("sorcerer.program").forget()
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
