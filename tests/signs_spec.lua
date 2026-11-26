local signs = require("sorcerer.signs")

describe("sorcerer.signs (scry's margin in code buffers)", function()
  local S = vim.diagnostic.severity
  local ns = vim.api.nvim_create_namespace("sorcerer_test_signs")
  local function diag(row, code, source, message)
    return { lnum = row, col = 0, end_lnum = row, end_col = 9, severity = S.WARN, source = source or "scry", code = code, message = message or "f adds two." }
  end
  local function marks(buf)
    local out = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, signs.sign_ns, 0, -1, { details = true })) do
      if m[4].sign_text then table.insert(out, { row = m[2], text = vim.trim(m[4].sign_text), hl = m[4].sign_hl_group, number = m[4].number_hl_group }) end
    end
    return out
  end
  local function texts(buf)
    local out = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, signs.sign_ns, 0, -1, { details = true })) do
      if m[4].virt_text then
        local t = ""
        for _, c in ipairs(m[4].virt_text) do t = t .. c[1] end
        table.insert(out, { row = m[2], text = t, hl = m[4].virt_text[1][2], pos = m[4].virt_text_pos })
      end
    end
    return out
  end
  local function code_buffer()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. "/src/scryme.py")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "def f(x):", "    return x + 2", "", "def g(y):", "    return y" })
    return buf
  end
  local function show(buf, ds)
    vim.diagnostic.set(ns, buf, ds)
    signs.place_signs(buf)
  end

  before_each(function() signs.setup({}) end)

  it("a bug draws ! in its own namespace on the finding's row, its line number tinted", function()
    local buf = code_buffer()
    show(buf, { diag(1, "bug") })
    local got = marks(buf)
    assert.equals(1, #got)
    assert.same({ row = 1, text = "!", hl = "SorcererBug", number = "SorcererBug" }, got[1])
  end)

  it("each issue type its glyph and its group; a stale finding is dimmed", function()
    local buf = code_buffer()
    show(buf, { diag(0, "assumption"), diag(1, "convention"), diag(3, "bug-stale"), diag(4, "design") })
    local got = marks(buf)
    assert.same({ "?", "§", "!", "~" }, { got[1].text, got[2].text, got[3].text, got[4].text })
    assert.same({ "SorcererAssumption", "SorcererConvention", "SorcererStale", "SorcererSign" }, { got[1].hl, got[2].hl, got[3].hl, got[4].hl })
    assert.same({ "SorcererAssumption", "SorcererConvention", "SorcererStale", "SorcererSign" }, { got[1].number, got[2].number, got[3].number, got[4].number })
  end)

  it("an issue type with no glyph gets the dot", function()
    local buf = code_buffer()
    show(buf, { diag(1, "naming") })
    assert.same({ row = 1, text = "•", hl = "SorcererSign", number = "SorcererSign" }, marks(buf)[1])
  end)

  it("an_unknown_issue_type_gets_the_dot (stale too, dimmed)", function()
    local buf = code_buffer()
    show(buf, { diag(1, "naming-stale") })
    assert.same({ row = 1, text = "•", hl = "SorcererStale", number = "SorcererStale" }, marks(buf)[1])
  end)

  it("the groups link to the diagnostic signs, and a bug's words to the error virtual text", function()
    local function link(name) return vim.api.nvim_get_hl(0, { name = name }).link end
    assert.equals("DiagnosticSignError", link("SorcererBug"))
    assert.equals("DiagnosticSignWarn", link("SorcererAssumption"))
    assert.equals("DiagnosticSignInfo", link("SorcererConvention"))
    assert.equals("DiagnosticVirtualTextError", link("SorcererBugText"))
    assert.equals("DiagnosticSignHint", link("SorcererSign"))
  end)

  it("a bug says its first sentence at the end of its line; other types say nothing there", function()
    local buf = code_buffer()
    show(buf, { diag(1, "bug", nil, "f adds two, not one. The caller expects one.\nrule: r1"), diag(3, "assumption"), diag(4, "convention") })
    local got = texts(buf)
    assert.equals(1, #got)
    assert.same({ row = 1, text = "! f adds two, not one.", hl = "SorcererBugText", pos = "eol" }, got[1])
  end)

  it("a long first sentence is cut to fit, with an ellipsis", function()
    local buf = code_buffer()
    local long = "the test " .. string.rep("never checks the booking was removed ", 4) .. "from the store."
    show(buf, { diag(1, "bug", nil, long) })
    local t = texts(buf)[1].text
    assert.equals(62, vim.fn.strchars(t))
    assert.equals("…", vim.fn.strcharpart(t, 61, 1))
  end)

  it("bug_text = false leaves the line's end alone", function()
    signs.setup({ bug_text = false })
    local buf = code_buffer()
    show(buf, { diag(1, "bug") })
    assert.same({}, texts(buf))
    assert.equals(1, #marks(buf))
  end)

  it("a stale bug's words are dimmed", function()
    local buf = code_buffer()
    show(buf, { diag(1, "bug-stale") })
    assert.equals("SorcererStale", texts(buf)[1].hl)
  end)

  it("a bug sharing its row with another finding still shows its sign and words", function()
    local buf = code_buffer()
    show(buf, { diag(1, "convention"), diag(1, "bug") })
    assert.equals("!", marks(buf)[1].text)
    assert.equals(1, #texts(buf))
  end)

  it("a finding on a row the buffer no longer has raises nothing", function()
    local buf = code_buffer()
    vim.diagnostic.set(ns, buf, { diag(4, "bug") })
    vim.api.nvim_buf_set_lines(buf, 1, -1, false, {})
    assert.has_no.errors(function() signs.place_signs(buf) end)
  end)

  it("two findings on a row draw one sign", function()
    local buf = code_buffer()
    show(buf, { diag(1, "bug"), diag(1, "convention") })
    assert.equals(1, #marks(buf))
  end)

  it("no scry finding, no sign; other sources are left to Neovim", function()
    local buf = code_buffer()
    show(buf, { diag(1, "some-rule", "other") })
    assert.same({}, marks(buf))
  end)

  it("Neovim's own signs and virtual text leave scry out", function()
    local buf = code_buffer()
    vim.diagnostic.config({ signs = true, virtual_text = true }, ns)
    show(buf, { diag(1, "bug"), diag(3, "some-rule", "other") })
    local sign_ns = vim.diagnostic.get_namespace(ns).user_data.sign_ns
    local rows = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, sign_ns, 0, -1, {})) do rows[m[2]] = true end
    assert.is_nil(rows[1])
    assert.is_true(rows[3])
  end)

  it("glyphs can be set", function()
    signs.setup({ signs = { bug = "B" } })
    local buf = code_buffer()
    show(buf, { diag(1, "bug") })
    assert.equals("B", marks(buf)[1].text)
  end)

  it("signs = false draws nothing and leaves the diagnostics to Neovim", function()
    signs.setup({ signs = false })
    local buf = code_buffer()
    vim.diagnostic.config({ signs = true }, ns)
    show(buf, { diag(1, "bug") })
    assert.same({}, marks(buf))
    local sign_ns = vim.diagnostic.get_namespace(ns).user_data.sign_ns
    assert.equals(1, #vim.api.nvim_buf_get_extmarks(buf, sign_ns, 0, -1, {}))
  end)

  describe("holes, rule findings and conjured changes", function()
    local function own(buf)
      local out = {}
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, signs.marks_ns, 0, -1, { details = true })) do
        table.insert(out, { row = m[2], col = m[3], text = m[4].sign_text and vim.trim(m[4].sign_text), hl = m[4].sign_hl_group or m[4].hl_group, number = m[4].number_hl_group, end_col = m[4].end_col })
      end
      return out
    end
    local function d(row, source, code, severity, extra)
      return vim.tbl_extend("force", { lnum = row, col = 0, end_lnum = row + 1, end_col = 0, severity = severity or S.INFO, source = source, code = code, message = "m" }, extra or {})
    end

    it("a hole draws the diamond and lights its placeholder", function()
      local buf = code_buffer()
      show(buf, { d(1, "spellbook", "hole", S.INFO, { col = 4, end_lnum = 1, end_col = 10 }) })
      local got = own(buf)
      assert.equals(2, #got)
      local glyph = vim.tbl_filter(function(m) return m.text end, got)[1]
      local span = vim.tbl_filter(function(m) return not m.text end, got)[1]
      assert.same({ row = 1, col = 0, text = "◇", hl = "SorcererHole" }, { row = glyph.row, col = glyph.col, text = glyph.text, hl = glyph.hl })
      assert.same({ 1, 4, 10, "SorcererHolePlaceholder" }, { span.row, span.col, span.end_col, span.hl })
    end)

    -- A diagnostic does not move with edits: after a formatter or a workspace edit it can name
    -- columns or rows the buffer no longer has, until its server publishes again.
    it("a hole whose span no longer fits its line draws the glyph and no span", function()
      local buf = code_buffer()
      show(buf, { d(4, "spellbook", "hole", S.INFO, { col = 48, end_lnum = 4, end_col = 58 }) })
      local got = own(buf)
      assert.equals(1, #got)
      assert.same({ 4, "◇" }, { got[1].row, got[1].text })
    end)

    it("a mark on a row the buffer no longer has draws nothing and raises nothing", function()
      local buf = code_buffer()
      vim.diagnostic.set(ns, buf, { d(2, "spellbook", "hole", S.INFO, { col = 4, end_lnum = 2, end_col = 10 }), d(3, "spellbook", "commands-use-ports", S.ERROR) })
      vim.api.nvim_buf_set_lines(buf, 1, -1, false, {})
      assert.has_no.errors(function() signs.place_signs(buf) end)
    end)

    it("a whole-line hole mark draws the glyph and no span", function()
      local buf = code_buffer()
      show(buf, { d(1, "spellbook", "hole") })
      assert.equals(1, #own(buf))
    end)

    it("a rule finding draws the identity glyph in its severity's group", function()
      local buf = code_buffer()
      show(buf, { d(0, "spellbook", "r1", S.ERROR), d(1, "spellbook", "r2", S.WARN), d(3, "spellbook", "r3", S.HINT) })
      local got = own(buf)
      assert.same({ "≡", "≡", "≡" }, { got[1].text, got[2].text, got[3].text })
      assert.same({ "SorcererRuleError", "SorcererRuleWarn", "SorcererRuleHint" }, { got[1].hl, got[2].hl, got[3].hl })
    end)

    it("a conjured change draws the star, its number tinted", function()
      local buf = code_buffer()
      show(buf, { d(1, "conjure", "change", S.INFO) })
      assert.same({ { row = 1, col = 0, text = "✦", hl = "SorcererConjured", number = "SorcererConjured" } }, own(buf))
    end)

    it("scry's own marks and other sources are untouched", function()
      local buf = code_buffer()
      show(buf, { diag(1, "bug"), d(3, "other", "x") })
      assert.same({}, own(buf))
      assert.equals(1, #marks(buf))
    end)

    it("the looks link to the diagnostic groups", function()
      local function link(name) return vim.api.nvim_get_hl(0, { name = name }).link end
      assert.equals("Special", link("SorcererHole"))
      assert.equals("DiagnosticUnderlineHint", link("SorcererHolePlaceholder"))
      assert.equals("DiagnosticSignError", link("SorcererRuleError"))
      assert.equals("DiagnosticSignOk", link("SorcererConjured"))
    end)

    it("Neovim's signs skip them while the look is on, and take them back when it is off", function()
      local function neovim_rows(buf)
        local sign_ns = vim.diagnostic.get_namespace(ns).user_data.sign_ns
        local rows = {}
        for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, sign_ns, 0, -1, {})) do rows[m[2]] = true end
        return rows
      end
      local buf = code_buffer()
      vim.diagnostic.config({ signs = true }, ns)
      show(buf, { d(1, "spellbook", "hole"), d(3, "conjure", "change") })
      assert.same({}, neovim_rows(buf))
      signs.setup({}, { spellbook = { signs = false }, conjure = { sign = false } })
      show(buf, { d(1, "spellbook", "hole"), d(3, "conjure", "change") })
      assert.same({}, own(buf))
      assert.is_true(neovim_rows(buf)[1])
      assert.is_true(neovim_rows(buf)[3])
    end)

    it("glyphs can be set", function()
      signs.setup({}, { spellbook = { signs = { hole = "H", rule = "R" } }, conjure = { sign = "C" } })
      local buf = code_buffer()
      show(buf, { d(0, "spellbook", "hole"), d(1, "spellbook", "r", S.ERROR), d(3, "conjure", "change") })
      local got = own(buf)
      assert.same({ "H", "R", "C" }, { got[1].text, got[2].text, got[3].text })
    end)
  end)
end)
