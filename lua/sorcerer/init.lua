-- sorcerer.nvim: scry (the sorcerer suite's reviewer) in Neovim. Saving a file makes scry
-- review what changed and put each verified finding on its line; nothing to say, nothing shown.
-- conjure (the writer) is opt-in beside it: a code action writes one change and marks it.
-- spellbook (generators with holes, and rules) is opt-in too: `:Spellbook new`.
-- lackey (an agent whose interface is the editor) is opt-in as well.
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
    -- the margin glyph of a conjured change; false gives Neovim's own display back
    sign = "✦",
  },
  -- off by default: it runs Claude Code on your own subscription
  lackey = {
    enabled = false,
    cmd = { "lackey", "lsp" },
  },
  -- off by default: a user without spellbook installed sees no start error
  spellbook = {
    enabled = false,
    cmd = { "spellbook", "lsp" },
    -- after `:Spellbook new`, run conjure on the first hole (needs conjure enabled too)
    conjure_holes = false,
    -- after `:Spellbook new`, the written file's holes work like snippet placeholders: these keys
    -- (insert and select mode, that buffer only) move between them; false = no session
    hole_keys = { next = "<Tab>", prev = "<S-Tab>" },
    -- how a hole and a rule finding look in the margin; false gives Neovim's own display back
    signs = { hole = "◇", rule = "≡" },
  },
  -- the grey `⟳ … working` text at the end of a line a server works on: its `⟳` spins (one
  -- 90 ms timer while anything is drawn); false keeps it still
  working = { animate = true },
  -- the code-action menu lists the preferred quick fixes first (a spellbook rule's fix), then the
  -- other quick fixes, then the rest, as VS Code does; false leaves Neovim's order
  fixes_first = true,
  -- sorcerer's keys, `<prefix><key>`; each needs its tool on. Set `keys = false`, or one key to
  -- `false`, to bind nothing (or that one). A lhs you already mapped is skipped.
  keys = {
    prefix = "<leader>m", new = "n", fix = "f", conjure = "c", undo = "u", try_harder = "t", why = "w", check = "k", sync = "s",
    -- lackey: do this, stop, show diff, undo the task, journal, dismiss, label, open the answer
    ["do"] = "a", stop = "q", diff = "d", undo_task = "z", journal = "j", dismiss = "x", label = "l", open_answer = "o",
  },
}

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
  -- a signs table replaces the default glyphs' keys it names; `false` must survive the merge
  if opts and opts.scry and opts.scry.signs == false then M.opts.scry.signs = false end
  if opts and opts.keys == false then M.opts.keys = false end
  if opts and opts.spellbook and opts.spellbook.signs == false then M.opts.spellbook.signs = false end
  if opts and opts.spellbook and opts.spellbook.hole_keys == false then M.opts.spellbook.hole_keys = false end
  if opts and opts.conjure and opts.conjure.sign == false then M.opts.conjure.sign = false end
  require("sorcerer.signs").setup(M.opts.scry, M.opts)
  require("sorcerer.working").setup(M.opts.working)
  -- the keys before the servers start: lackey tells its server the open-answer key
  require("sorcerer.keys").setup(M.opts)
  require("sorcerer.scry").setup(M.opts.scry)
  require("sorcerer.conjure").setup(M.opts.conjure)
  require("sorcerer.spellbook").setup(M.opts.spellbook)
  require("sorcerer.lackey").setup(M.opts.lackey)
  require("sorcerer.code_actions").setup(M.opts.fixes_first)
end

-- For a status line: "scry: reviewing 2 units" while scry reviews, "conjure: conjuring a
-- change" while conjure writes (both, joined by two spaces, when both work), else "".
function M.status()
  local lines = {}
  local statuses = {
    require("sorcerer.scry").status(),
    require("sorcerer.conjure").status(),
    require("sorcerer.spellbook").status(),
    require("sorcerer.lackey").status(),
  }
  for _, line in ipairs(statuses) do
    if line ~= "" then table.insert(lines, line) end
  end
  return table.concat(lines, "  ")
end

return M
