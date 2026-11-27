-- lackey in Neovim: opt-in, one client a root named `lackey`, attached to every buffer
-- under the root with `debounce_text_changes = 0`, announcing the notifications it draws, and
-- drawing them: ghost lines, a note beside the code, a diff against the text before; the keys;
-- the status line. The fake `lackey lsp` is the fake-lsp.
local sorcerer = require("sorcerer")
local lackey = require("sorcerer.lackey")
local keys = require("sorcerer.keys")
local fake = vim.fn.fnamemodify("tests/fake-lsp", ":p")

local function wait(pred, ms) assert(vim.wait(ms or 5000, pred, 10), "timed out") end
local function clients() return vim.lsp.get_clients({ name = "lackey" }) end

local function project()
  local root = vim.fn.resolve(vim.fn.tempname())
  vim.fn.mkdir(root .. "/.git", "p")
  vim.fn.mkdir(root .. "/src", "p")
  vim.fn.writefile({ "def f(x):", "    pass", "" }, root .. "/src/a.py")
  vim.fn.writefile({ "x = 1" }, root .. "/src/b.py")
  return root
end

local function stop_all()
  for _, c in ipairs(clients()) do c:stop(true) end
  wait(function() return #clients() == 0 end)
end

local function unmap_all()
  for _, key in ipairs({ "a", "q", "d", "z", "j", "x", "l" }) do pcall(vim.keymap.del, "n", "<leader>m" .. key) end
end

local function started()
  local root = project()
  vim.cmd.edit(root .. "/src/a.py")
  wait(function() return #clients() == 1 and clients()[1].initialized end)
  return root, clients()[1]
end

describe("sorcerer.lackey", function()
  before_each(function()
    stop_all()
    unmap_all()
    vim.cmd("silent! %bwipeout!")
    vim.cmd("silent! only")
    vim.env.FAKE_LSP_LOG = vim.fn.tempname()
    vim.env.FAKE_LSP_NAME = "lackey"
    sorcerer.setup({ scry = { enabled = false }, lackey = { enabled = true, cmd = { fake, "lsp" } } })
  end)
  after_each(function()
    vim.env.FAKE_LSP_NAME = nil
    unmap_all()
  end)

  it("stays off by default", function()
    stop_all()
    sorcerer.setup({ scry = { enabled = false } })
    local root = project()
    vim.cmd.edit(root .. "/src/a.py")
    vim.wait(300)
    assert.equals(0, #clients())
    assert.is_false(sorcerer.defaults.lackey.enabled)
  end)

  it("starts on a root with debounce 0 and says what it draws", function()
    local root, c = started()
    assert.equals(root, c.config.root_dir)
    assert.equals(0, c.config.flags.debounce_text_changes)
    assert.equals(true, c.config.init_options.drawsWorking)
    assert.same({ "sorcerer/ghost", "sorcerer/note", "sorcerer/showDiff" }, c.config.init_options.handles)
    -- the open-answer key, so a long answer's mark names it
    assert.same({ openAnswer = "<leader>mo" }, c.config.init_options.keys)
  end)

  it("attaches to every buffer under the root", function()
    local root, c = started()
    local hidden = vim.fn.bufadd(root .. "/src/b.py")
    vim.fn.bufload(hidden)
    wait(function() return c.attached_buffers[hidden] end)
  end)

  it("attaches to a file its edit creates before it is on disk", function()
    local root, c = started()
    local new = root .. "/src/late/lateness.py"
    local uri = vim.uri_from_fname(new)
    vim.lsp.util.apply_workspace_edit({
      documentChanges = {
        { kind = "create", uri = uri, options = { ignoreIfExists = true } },
        {
          textDocument = { uri = uri, version = vim.NIL },
          edits = { { range = { start = { line = 0, character = 0 }, ["end"] = { line = 1, character = 0 } }, newText = "x = 1\n" } },
        },
      },
    }, "utf-16")
    assert.is_nil(vim.uv.fs_stat(new))
    local buf = vim.fn.bufnr(new)
    wait(function() return c.attached_buffers[buf] end)
  end)

  it("draws ghost lines under a line and takes them away", function()
    local root, c = started()
    local uri = vim.uri_from_fname(root .. "/src/a.py")
    c.handlers["sorcerer/ghost"](nil, { uri = uri, line = 0, lines = { "    return x", "# done" } }, { client_id = c.id })
    local marks = vim.api.nvim_buf_get_extmarks(0, lackey.ghost_ns, 0, -1, { details = true })
    assert.equals(1, #marks)
    assert.equals("    return x", marks[1][4].virt_lines[1][1][1])
    assert.equals("# done", marks[1][4].virt_lines[2][1][1])
    c.handlers["sorcerer/ghost"](nil, { uri = uri, line = 0, lines = {} }, { client_id = c.id })
    assert.same({}, vim.api.nvim_buf_get_extmarks(0, lackey.ghost_ns, 0, -1, {}))
  end)

  it("an edit of the line takes its ghost away", function()
    local root, c = started()
    local uri = vim.uri_from_fname(root .. "/src/a.py")
    c.handlers["sorcerer/ghost"](nil, { uri = uri, line = 0, lines = { "hint" } }, { client_id = c.id })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.api.nvim_buf_set_lines(0, 0, 1, false, { "def g(x):" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
    assert.same({}, vim.api.nvim_buf_get_extmarks(0, lackey.ghost_ns, 0, -1, {}))
  end)

  it("an edit in a window that is not the current one takes that line's ghost away", function()
    local root, c = started()
    local buf = vim.api.nvim_get_current_buf()
    local uri = vim.uri_from_fname(root .. "/src/a.py")
    c.handlers["sorcerer/ghost"](nil, { uri = uri, line = 0, lines = { "hint" } }, { client_id = c.id })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    -- another window, on a scratch buffer of three lines, with its cursor on the last
    vim.cmd("split")
    vim.cmd("enew")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "def g(x):" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
    assert.same({}, vim.api.nvim_buf_get_extmarks(buf, lackey.ghost_ns, 0, -1, {}))
  end)

  it("opens a note beside the code and keeps the cursor", function()
    local root, c = started()
    local note = root .. "/note.md"
    vim.fn.writefile({ "# Research" }, note)
    local here = vim.api.nvim_get_current_win()
    c.handlers["sorcerer/note"](nil, { uri = vim.uri_from_fname(note) }, { client_id = c.id })
    assert.equals(2, #vim.api.nvim_tabpage_list_wins(0))
    assert.equals(here, vim.api.nvim_get_current_win())
    assert.truthy(vim.fn.bufnr(note) > 0)
  end)

  it("shows the text before against the live buffer in diff mode", function()
    local root, c = started()
    local uri = vim.uri_from_fname(root .. "/src/a.py")
    c.handlers["sorcerer/showDiff"](nil, { uri = uri, before = "def f(y):\n    pass\n", title = "lackey: before" }, { client_id = c.id })
    local wins = vim.api.nvim_tabpage_list_wins(0)
    assert.equals(2, #wins)
    for _, win in ipairs(wins) do assert.is_true(vim.wo[win].diff) end
    local scratch = vim.tbl_filter(function(win) return vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "nofile" end, wins)[1]
    assert.same({ "def f(y):", "    pass" }, vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(scratch), 0, -1, false))
    assert.equals(vim.fn.bufnr(root .. "/src/a.py"), vim.api.nvim_get_current_buf())
  end)

  it("shows the diff while another buffer has unsaved changes", function()
    local root, c = started()
    vim.o.hidden = false
    vim.cmd.edit(root .. "/src/b.py")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "x = 2" })
    local uri = vim.uri_from_fname(root .. "/src/a.py")
    c.handlers["sorcerer/showDiff"](nil, { uri = uri, before = "", title = "lackey: before" }, { client_id = c.id })
    vim.o.hidden = true
    assert.equals(vim.fn.bufnr(root .. "/src/a.py"), vim.api.nvim_get_current_buf())
    assert.is_true(vim.wo.diff)
  end)

  it("binds its keys under <leader>m when it is on", function()
    for _, key in ipairs({ "a", "q", "d", "z", "j", "x", "l" }) do assert.truthy(vim.fn.maparg("<leader>m" .. key, "n") ~= "", key) end
    assert.equals("<leader>ma", keys.lhs("do"))
    assert.equals("<leader>ml", keys.lhs("label"))
    assert.equals("<leader>mq", keys.lhs("stop"))
  end)

  it("the do key runs the offer whatever its price, and only it", function()
    local applied
    local real = vim.lsp.buf.code_action
    vim.lsp.buf.code_action = function(o) applied = o end
    vim.fn.maparg("<leader>ma", "n", false, true).callback()
    vim.lsp.buf.code_action = real
    assert.is_true(applied.apply)
    assert.is_true(applied.filter({ title = "lackey: do this · ~$0.50 · sonnet" }))
    assert.is_false(applied.filter({ title = "lackey: Dismiss" }))
  end)

  it("the label key lists the four labels to pick from", function()
    local applied
    local real = vim.lsp.buf.code_action
    vim.lsp.buf.code_action = function(o) applied = o end
    vim.fn.maparg("<leader>ml", "n", false, true).callback()
    vim.lsp.buf.code_action = real
    assert.is_false(applied.apply)
    assert.is_true(applied.filter({ title = "lackey: this was a claim" }))
    assert.is_false(applied.filter({ title = "lackey: do this · ~$0.50 · sonnet" }))
  end)

  it("status follows the task's progress", function()
    local _, c = started()
    assert.equals("", sorcerer.status())
    vim.api.nvim_exec_autocmds("LspProgress", {
      data = { client_id = c.id, params = { token = "t", value = { kind = "begin", message = "refuse late cancellations · reading a.py · $0.00" } } },
    })
    assert.equals("lackey: refuse late cancellations · reading a.py · $0.00", sorcerer.status())
    vim.api.nvim_exec_autocmds("LspProgress", { data = { client_id = c.id, params = { token = "t", value = { kind = "end" } } } })
    assert.equals("", sorcerer.status())
  end)
end)
