-- scry's margin in code buffers: one sign a row for the findings scry publishes (source
-- `scry`, code = the issue type, `<type>-stale` when the unit changed since the review),
-- each issue type its own group with the line number tinted the same; a bug also says its
-- statement's first sentence at the end of its line. Neovim's own signs and virtual text
-- skip scry's diagnostics, so a finding shows once; its words are whole in the diagnostic
-- float and in scry's "Show why" action.
local M = {}

M.sign_ns = vim.api.nvim_create_namespace("sorcerer_scry_signs")
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
end

-- The first sentence of MESSAGE's first line, cut to WIDTH characters with an ellipsis.
local function first_sentence(message, width)
  local line = vim.trim(vim.split(tostring(message or ""), "\n", { plain = true })[1] or "")
  local sentence = line:match("^(.-[%.!?])%s") or line
  if vim.fn.strchars(sentence) > width then sentence = vim.fn.strcharpart(sentence, 0, width - 1) .. "…" end
  return sentence
end

-- Neovim's handler NAME, showing everything but scry's findings (wrapped once a session;
-- `signs = false` turns the skipping off again).
local wrapped = {}
local function without_scry(name)
  local h = vim.diagnostic.handlers[name]
  if wrapped[name] or not h or not h.show then return end
  wrapped[name] = true
  local show = h.show
  h.show = function(namespace, bufnr, diagnostics, opts)
    if not M.enabled then return show(namespace, bufnr, diagnostics, opts) end
    local keep = {}
    for _, d in ipairs(diagnostics) do
      if d.source ~= "scry" then table.insert(keep, d) end
    end
    return show(namespace, bufnr, keep, opts)
  end
end

function M.place_signs(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, M.sign_ns, 0, -1)
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
function M.setup(opts)
  opts = opts or {}
  M.enabled = opts.signs ~= false
  M.glyphs = vim.tbl_extend("force", M.default_glyphs, type(opts.signs) == "table" and opts.signs or {})
  M.bug_text = opts.bug_text ~= false
  M.set_highlights()
  without_scry("signs")
  without_scry("virtual_text")
  local group = vim.api.nvim_create_augroup("sorcerer_signs", { clear = true })
  vim.api.nvim_create_autocmd("DiagnosticChanged", { group = group, callback = function(a) M.place_signs(a.buf) end })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = M.set_highlights })
end

return M
