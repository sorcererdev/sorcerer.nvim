-- sorcerer.nvim: scry (the sorcerer suite's reviewer) in Neovim. Saving a file makes scry
-- review what changed and put each verified finding on its line; nothing to say, nothing shown.
local M = {}

M.defaults = {
  scry = {
    enabled = true,
    cmd = { "scry", "lsp" },
    -- a glyph per issue type; false leaves scry's diagnostics to Neovim's own display
    signs = { bug = "!", assumption = "?", convention = "§", design = "~" },
    -- a bug's first sentence at the end of its line
    bug_text = true,
  },
}

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
  -- a signs table replaces the default glyphs' keys it names; `false` must survive the merge
  if opts and opts.scry and opts.scry.signs == false then M.opts.scry.signs = false end
  require("sorcerer.signs").setup(M.opts.scry)
  require("sorcerer.scry").setup(M.opts.scry)
end

-- For a status line: "scry: reviewing 2 units" while scry reviews, else "".
function M.status()
  return require("sorcerer.scry").status()
end

return M
