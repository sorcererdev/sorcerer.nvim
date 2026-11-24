-- scry's margin in code buffers: one sign a row for the findings scry publishes (source
-- `scry`, code = the issue type, `<type>-stale` when the unit changed since the review),
-- each issue type its own group with the line number tinted the same; a bug also says its
-- statement's first sentence at the end of its line. Neovim's own signs and virtual text
-- skip scry's diagnostics, so a finding shows once; its words are whole in the diagnostic
-- float and in scry's "Show why" action.
-- Three more kinds of mark are told apart from scry's and from each other, each its own glyph
-- and group, drawn here in the `sorcerer_marks` namespace (Neovim's own display skips them
-- while their look is on): a spellbook hole `◇` (SorcererHole, the placeholder itself in
-- SorcererHolePlaceholder), a spellbook rule finding `≡` (SorcererRuleError/Warn/Hint by
-- severity) and a conjured change `✦` (SorcererConjured). A glyph set to `false` gives that
-- kind back to Neovim's own display.
local M = {}

M.sign_ns = vim.api.nvim_create_namespace("sorcerer_scry_signs")
M.marks_ns = vim.api.nvim_create_namespace("sorcerer_marks")
M.default_looks = { hole = "◇", rule = "≡", conjured = "✦" }
M.looks = vim.deepcopy(M.default_looks)
M.default_glyphs = { bug = "!", assumption = "?", convention = "§", design = "~" }
M.glyphs = vim.deepcopy(M.default_glyphs)
M.fallback_glyph = "•"
M.bug_text = true
M.enabled = true
M.bug_text_width = 60

-- each issue type's sign (and line number) group; any other type gets SorcererSign
M.groups = { bug = "SorcererBug", assumption = "SorcererAssumption", convention = "SorcererConvention" }

function M.set_highlights()
  vim.api.nvim_set_hl(0, "SorcererSign", { link = "DiagnosticSignHint", default = true })
  vim.api.nvim_set_hl(0, "SorcererBug", { link = "DiagnosticSignError", default = true })
  vim.api.nvim_set_hl(0, "SorcererAssumption", { link = "DiagnosticSignWarn", default = true })
  vim.api.nvim_set_hl(0, "SorcererConvention", { link = "DiagnosticSignInfo", default = true })
  vim.api.nvim_set_hl(0, "SorcererBugText", { link = "DiagnosticVirtualTextError", default = true })
  vim.api.nvim_set_hl(0, "SorcererStale", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "SorcererHole", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "SorcererHolePlaceholder", { link = "DiagnosticUnderlineHint", default = true })
  vim.api.nvim_set_hl(0, "SorcererRuleError", { link = "DiagnosticSignError", default = true })
  vim.api.nvim_set_hl(0, "SorcererRuleWarn", { link = "DiagnosticSignWarn", default = true })
  vim.api.nvim_set_hl(0, "SorcererRuleHint", { link = "DiagnosticSignHint", default = true })
  vim.api.nvim_set_hl(0, "SorcererConjured", { link = "DiagnosticSignOk", default = true })
end

-- The first sentence of MESSAGE's first line, cut to WIDTH characters with an ellipsis.
local function first_sentence(message, width)
  local line = vim.trim(vim.split(tostring(message or ""), "\n", { plain = true })[1] or "")
  local sentence = line:match("^(.-[%.!?])%s") or line
  if vim.fn.strchars(sentence) > width then sentence = vim.fn.strcharpart(sentence, 0, width - 1) .. "…" end
  return sentence
end

-- Which look a spellbook or conjure diagnostic D has ("hole", "rule", "conjured"), or nil.
local function look_of(d)
  if d.source == "spellbook" then return d.code == "hole" and "hole" or "rule" end
  if d.source == "conjure" and d.code == "change" then return "conjured" end
end

-- Neovim's handler NAME, showing everything but what sorcerer draws itself: scry's findings
-- (while `scry.signs` is on) and, for the signs handler only, holes, rule findings and
-- conjured changes whose look is on. Wrapped once a session; turning a look off turns the
-- skipping off again.
local wrapped = {}
local function without_own(name)
  local h = vim.diagnostic.handlers[name]
  if wrapped[name] or not h or not h.show then return end
  wrapped[name] = true
  local show = h.show
  h.show = function(namespace, bufnr, diagnostics, opts)
    local keep = {}
    for _, d in ipairs(diagnostics) do
      local ours = (d.source == "scry" and M.enabled) or (name == "signs" and M.looks[look_of(d)])
      if not ours then table.insert(keep, d) end
    end
    return show(namespace, bufnr, keep, opts)
  end
end

local severity_groups = {
  [vim.diagnostic.severity.ERROR] = "SorcererRuleError",
  [vim.diagnostic.severity.WARN] = "SorcererRuleWarn",
  [vim.diagnostic.severity.INFO] = "SorcererRuleHint",
  [vim.diagnostic.severity.HINT] = "SorcererRuleHint",
}

-- Draw the hole, rule and conjured marks of buffer BUF.
local function place_marks(buf)
  for _, d in ipairs(vim.diagnostic.get(buf)) do
    local look = look_of(d)
    local glyph = look and M.looks[look]
    if glyph then
      local mark
      if look == "hole" then
        mark = { sign_text = glyph, sign_hl_group = "SorcererHole", priority = 15 }
        -- the placeholder itself, when the server gave its span (a whole-line range spans lines)
        if d.end_lnum == nil or d.end_lnum == d.lnum then
          local end_col = d.end_col
          if end_col and end_col > d.col then
            vim.api.nvim_buf_set_extmark(buf, M.marks_ns, d.lnum, d.col, { end_row = d.lnum, end_col = end_col, hl_group = "SorcererHolePlaceholder", priority = 15 })
          end
        end
      elseif look == "rule" then
        local group = severity_groups[d.severity] or "SorcererRuleHint"
        mark = { sign_text = glyph, sign_hl_group = group, priority = 18 }
      else
        mark = { sign_text = glyph, sign_hl_group = "SorcererConjured", number_hl_group = "SorcererConjured", priority = 25 }
      end
      vim.api.nvim_buf_set_extmark(buf, M.marks_ns, d.lnum, 0, mark)
    end
  end
end

function M.place_signs(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, M.sign_ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, M.marks_ns, 0, -1)
  place_marks(buf)
  if not M.enabled then return end
  -- one finding a row: a bug before any other type
  local rows, order = {}, {}
  for _, d in ipairs(vim.diagnostic.get(buf)) do
    if d.source == "scry" then
      local kind, stale = tostring(d.code or ""):gsub("%-stale$", "")
      local had = rows[d.lnum]
      if not had then table.insert(order, d.lnum) end
      if not had or (kind == "bug" and had.kind ~= "bug") then rows[d.lnum] = { d = d, kind = kind, stale = stale > 0 } end
    end
  end
  for _, lnum in ipairs(order) do
    local f = rows[lnum]
    local group = f.stale and "SorcererStale" or (M.groups[f.kind] or "SorcererSign")
    local mark = { sign_text = M.glyphs[f.kind] or M.fallback_glyph, sign_hl_group = group, number_hl_group = group, priority = 20 }
    if f.kind == "bug" and M.bug_text then
      mark.virt_text = { { (M.glyphs.bug or "!") .. " " .. first_sentence(f.d.message, M.bug_text_width), f.stale and "SorcererStale" or "SorcererBugText" } }
      mark.virt_text_pos = "eol"
    end
    vim.api.nvim_buf_set_extmark(buf, M.sign_ns, lnum, 0, mark)
  end
end

-- OPTS is the `scry` table of setup: `signs` (glyphs by issue type, or false) and `bug_text`.
-- ALL, when given, is the whole setup table: it holds the looks of holes (`spellbook.signs.hole`),
-- rule findings (`spellbook.signs.rule`) and conjured changes (`conjure.sign`).
function M.setup(opts, all)
  opts = opts or {}
  all = all or {}
  local book, conj = all.spellbook or {}, all.conjure or {}
  local book_signs = book.signs
  M.looks = {
    hole = (book_signs ~= false) and (type(book_signs) == "table" and book_signs.hole or M.default_looks.hole) or nil,
    rule = (book_signs ~= false) and (type(book_signs) == "table" and book_signs.rule or M.default_looks.rule) or nil,
    conjured = (conj.sign ~= false) and (conj.sign or M.default_looks.conjured) or nil,
  }
  for _, kind in ipairs({ "hole", "rule" }) do
    if type(book_signs) == "table" and book_signs[kind] == false then M.looks[kind] = nil end
  end
  M.enabled = opts.signs ~= false
  M.glyphs = vim.tbl_extend("force", M.default_glyphs, type(opts.signs) == "table" and opts.signs or {})
  M.bug_text = opts.bug_text ~= false
  M.set_highlights()
  without_own("signs")
  without_own("virtual_text")
  local group = vim.api.nvim_create_augroup("sorcerer_signs", { clear = true })
  vim.api.nvim_create_autocmd("DiagnosticChanged", { group = group, callback = function(a) M.place_signs(a.buf) end })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = M.set_highlights })
end

return M
