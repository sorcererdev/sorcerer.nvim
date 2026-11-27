-- the grey `⟳ scry: reviewing…` after a unit's first line: drawn from the server's
-- `sorcerer/working`, moved by edits, gone when the server says it is done or exits.
local sorcerer = require("sorcerer")
local working = require("sorcerer.working")
local fake = vim.fn.fnamemodify("tests/fake-lsp", ":p")

local function wait(pred, ms) assert(vim.wait(ms or 5000, pred, 10), "timed out") end
local function clients() return vim.lsp.get_clients({ name = "scry" }) end

-- the marks `working` has drawn in buffer BUF: { row, text, hl }
local function drawn(buf)
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf or 0, working.ns, 0, -1, { details = true })) do
    local chunk = m[4].virt_text[1]
    table.insert(out, { m[2], chunk[1], chunk[2], m[4].virt_text_pos })
  end
  return out
end

local function project()
  local root = vim.fn.resolve(vim.fn.tempname())
  vim.fn.mkdir(root .. "/.git", "p")
  vim.fn.mkdir(root .. "/src", "p")
  vim.fn.writefile({ "def f(x):", "    return x + 2", "" }, root .. "/src/a.py")
  return root
end

local function stop_all()
  for _, c in ipairs(clients()) do c:stop(true) end
  wait(function() return #clients() == 0 end)
end

describe("sorcerer.working", function()
  before_each(function()
    stop_all()
    vim.cmd("silent! %bwipeout!")
    vim.env.FAKE_LSP_LOG = vim.fn.tempname()
    vim.env.FAKE_LSP_REPLIES = vim.fn.tempname()
    vim.fn.mkdir(vim.env.FAKE_LSP_REPLIES, "p")
    vim.fn.writefile({ "[]" }, vim.env.FAKE_LSP_REPLIES .. "/diagnostics.json")
    sorcerer.setup({ scry = { cmd = { fake, "lsp" } } })
  end)

  local function save_a_file()
    local root = project()
    vim.cmd.edit(root .. "/src/a.py")
    wait(function() return #clients() == 1 and clients()[1].initialized end)
    vim.cmd.write()
  end

  it("tells the server it draws the units", function()
    local root = project()
    vim.cmd.edit(root .. "/src/a.py")
    wait(function() return #clients() == 1 and clients()[1].initialized end)
    assert.equals(true, clients()[1].config.init_options.drawsWorking)
  end)

  it("draws grey text at the end of the unit's first line, and clears it when the review ends", function()
    save_a_file()
    wait(function() return #drawn() == 1 end)
    assert.same({ { 0, "⠋ scry: reviewing…", "SorcererWorking", "eol" } }, drawn())
    assert.equals("Comment", vim.api.nvim_get_hl(0, { name = "SorcererWorking", link = true }).link)
    wait(function() return #drawn() == 0 end)
  end)

  it("follows edits above it", function()
    save_a_file()
    wait(function() return #drawn() == 1 end)
    vim.api.nvim_buf_set_lines(0, 0, 0, false, { "# a comment" })
    assert.equals(1, drawn()[1][1])
    wait(function() return #drawn() == 0 end)
  end)

  it("is gone when the server exits mid-review", function()
    save_a_file()
    wait(function() return #drawn() == 1 end)
    clients()[1]:stop(true)
    wait(function() return #drawn() == 0 end)
  end)

  it("a notification for a file that is not open draws nothing and does not open it", function()
    local root = project()
    vim.cmd.edit(root .. "/src/a.py")
    wait(function() return #clients() == 1 and clients()[1].initialized end)
    local other = root .. "/src/other.py"
    working.show(clients()[1].id, { { uri = vim.uri_from_fname(other), line = 0, text = "x" } })
    assert.equals(-1, vim.fn.bufnr(other))
  end)

  describe("the spinning ⟳", function()
    local id = 9001
    local function unit(buf, text)
      return { uri = vim.uri_from_fname(vim.api.nvim_buf_get_name(buf)), line = 0, text = text or "⟳ apprentice: researching…" }
    end
    -- whether TEXT is one of the frames, then the unit's words
    local function spinning(text)
      for _, f in ipairs(working.frames) do
        if text == f .. " apprentice: researching…" then return true end
      end
      return false
    end
    local function a_shown_buffer()
      local root = project()
      vim.cmd.edit(root .. "/src/a.py")
      return vim.api.nvim_get_current_buf()
    end
    after_each(function()
      working.clear(id)
      working.setup({ animate = true })
    end)

    it("starts a timer with the first mark, cycles the frames, and stops with the last", function()
      local buf = a_shown_buffer()
      assert.is_false(working.animating())
      working.show(id, { unit(buf) })
      assert.is_true(working.animating())
      local first = drawn(buf)[1][2]
      assert.is_true(spinning(first), first)
      wait(function() return drawn(buf)[1][2] ~= first end, 1000)
      assert.is_true(spinning(drawn(buf)[1][2]))
      working.show(id, {})
      assert.is_false(working.animating())
      assert.same({}, drawn(buf))
    end)

    it("one timer serves every client, and runs until the last client's marks go", function()
      local buf = a_shown_buffer()
      working.show(id, { unit(buf) })
      working.show(id + 1, { unit(buf, "⟳ scry: reviewing…") })
      working.clear(id)
      assert.is_true(working.animating())
      working.clear(id + 1)
      assert.is_false(working.animating())
    end)

    it("leaves a hidden buffer's mark as it is", function()
      local buf = a_shown_buffer()
      working.show(id, { unit(buf) })
      vim.cmd("enew")
      local hidden = drawn(buf)[1][2]
      vim.wait(400)
      assert.equals(hidden, drawn(buf)[1][2])
    end)

    it("animate = false keeps the ⟳ and runs no timer", function()
      working.setup({ animate = false })
      local buf = a_shown_buffer()
      working.show(id, { unit(buf) })
      assert.is_false(working.animating())
      assert.equals("⟳ apprentice: researching…", drawn(buf)[1][2])
    end)
  end)
end)
