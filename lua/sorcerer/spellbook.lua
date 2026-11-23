-- spellbook's language server: `spellbook lsp`, the sorcerer suite's generators and rules. The
-- server shows each open hole of a generated file as a mark (a diagnostic) on save and open, and
-- runs the four commands `:Spellbook new` asks with Neovim's own pickers.
-- spellbook is attached to every buffer under the project root, so it sees each file opened or
-- saved; one client a project root (Neovim reuses a client with the same name and root). The
-- root is the nearest `.sorcerer/` upward, else the nearest `.git`, the server's own order.
local M = {}

local opts = nil

-- The project root of buffer BUF, or nil.
function M.root(buf)
  return vim.fs.root(buf, ".sorcerer") or vim.fs.root(buf, ".git")
end

-- Attach spellbook to buffer BUF when it is enabled and BUF is a file under a project root.
function M.attach(buf)
  if not opts or not opts.enabled then return end
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then return end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or not vim.uv.fs_stat(name) then return end
  local root = M.root(buf)
  if not root then return end
  if not require("sorcerer.program").runnable("spellbook", opts.cmd) then return end
  vim.lsp.start({ name = "spellbook", cmd = opts.cmd, root_dir = root }, { bufnr = buf })
end

-- spellbook shows no progress line, so it has nothing for the status line.
function M.status()
  return ""
end

-- OPTS is the `spellbook` table of setup.
function M.setup(o)
  opts = o
  require("sorcerer.program").forget()
  local group = vim.api.nvim_create_augroup("sorcerer_spellbook", { clear = true })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufWritePost", "BufEnter" }, {
    group = group,
    callback = function(a) M.attach(a.buf) end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then M.attach(buf) end
  end
end

return M
