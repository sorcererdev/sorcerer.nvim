-- sorcerer.nvim: scry (the sorcerer suite's reviewer) in Neovim. Saving a file makes scry
-- review what changed and put each verified finding on its line; nothing to say, nothing shown.
-- conjure (the writer) is opt-in beside it: a code action writes one change and marks it.
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
  -- off by default: a scry user without conjure installed sees no start error
  conjure = {
    enabled = false,
    cmd = { "conjure", "lsp" },
  },
}

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
  -- a signs table replaces the default glyphs' keys it names; `false` must survive the merge
  if opts and opts.scry and opts.scry.signs == false then M.opts.scry.signs = false end
  require("sorcerer.signs").setup(M.opts.scry)
  require("sorcerer.scry").setup(M.opts.scry)
  require("sorcerer.conjure").setup(M.opts.conjure)
end

-- For a status line: "scry: reviewing 2 units" while scry reviews, "conjure: conjuring a
-- change" while conjure writes (both, joined by two spaces, when both work), else "".
function M.status()
  local lines = {}
  for _, line in ipairs({ require("sorcerer.scry").status(), require("sorcerer.conjure").status() }) do
    if line ~= "" then table.insert(lines, line) end
  end
  return table.concat(lines, "  ")
end

return M
