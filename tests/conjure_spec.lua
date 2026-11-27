-- conjure in Neovim: opt-in, one client a root named `conjure`, attached to every buffer
-- under the root, started with `debounce_text_changes = 0`; the fake `conjure lsp`.
local sorcerer = require("sorcerer")
local fake = vim.fn.fnamemodify("tests/fake-lsp", ":p")

local function wait(pred, ms) assert(vim.wait(ms or 5000, pred, 10), "timed out") end
local function clients(name) return vim.lsp.get_clients({ name = name or "conjure" }) end

-- a temp project: ".git" at the top, src/a.py, src/b.py and notes.txt
local function project()
  local root = vim.fn.resolve(vim.fn.tempname())
  vim.fn.mkdir(root .. "/.git", "p")
  vim.fn.mkdir(root .. "/src", "p")
  vim.fn.writefile({ "def f(x):", "    pass", "" }, root .. "/src/a.py")
  vim.fn.writefile({ "x = 1" }, root .. "/src/b.py")
  vim.fn.writefile({ "notes" }, root .. "/notes.txt")
  return root
end

local function stop_all()
  for _, name in ipairs({ "conjure", "scry" }) do
    for _, c in ipairs(clients(name)) do c:stop(true) end
  end
  wait(function() return #clients() == 0 and #clients("scry") == 0 end)
end

-- a progress message from the client NAME, as the server sends it
local function progress(name, kind, message)
  vim.api.nvim_exec_autocmds("LspProgress", {
    data = { client_id = clients(name)[1].id, params = { token = "t", value = { kind = kind, message = message } } },
  })
end

describe("sorcerer.conjure", function()
  before_each(function()
    stop_all()
    vim.cmd("silent! %bwipeout!")
    vim.env.FAKE_LSP_LOG = vim.fn.tempname()
    sorcerer.setup({ scry = { enabled = false }, conjure = { enabled = true, cmd = { fake, "lsp" } } })
  end)

  it("conjure starts on a root when enabled", function()
    local root = project()
    vim.cmd.edit(root .. "/src/a.py")
    wait(function() return #clients() == 1 end)
    assert.equals(root, clients()[1].config.root_dir)
    assert.equals(0, #clients("scry"))
  end)

  it("conjure stays off by default", function()
    stop_all()
    sorcerer.setup({ scry = { enabled = false, cmd = { fake, "lsp" } } })
    local root = project()
    vim.cmd.edit(root .. "/src/a.py")
    vim.wait(300)
    assert.equals(0, #clients())
    assert.is_false(require("sorcerer").defaults.conjure.enabled)
  end)

  it("conjure is started with debounce_text_changes = 0", function()
    local root = project()
    vim.cmd.edit(root .. "/src/a.py")
    wait(function() return #clients() == 1 end)
    assert.equals(0, clients()[1].config.flags.debounce_text_changes)
  end)

  it("conjure draws what it is writing: it says so at initialize and takes the units", function()
    local root = project()
    vim.cmd.edit(root .. "/src/a.py")
    wait(function() return #clients() == 1 and clients()[1].initialized end)
    local c = clients()[1]
    assert.equals(true, c.config.init_options.drawsWorking)
    c.handlers["sorcerer/working"](nil, { units = { { uri = vim.uri_from_fname(root .. "/src/a.py"), line = 0, text = "⟳ conjure: writing…" } } }, { client_id = c.id })
    local marks = vim.api.nvim_buf_get_extmarks(0, require("sorcerer.working").ns, 0, -1, { details = true })
    -- the ⟳ spins: its first frame is drawn at once
    assert.equals("⠋ conjure: writing…", marks[1][4].virt_text[1][1])
    c.handlers["sorcerer/working"](nil, { units = {} }, { client_id = c.id })
    assert.same({}, vim.api.nvim_buf_get_extmarks(0, require("sorcerer.working").ns, 0, -1, {}))
  end)

  it("conjure attaches to every buffer under the root, of any kind of file", function()
    local root = project()
    vim.cmd.edit(root .. "/src/a.py")
    vim.cmd.edit(root .. "/notes.txt")
    -- a buffer loaded without being shown, as Neovim does for an edit to a file not open
    local hidden = vim.fn.bufadd(root .. "/src/b.py")
    vim.fn.bufload(hidden)
    wait(function() return #clients() == 1 and vim.tbl_count(clients()[1].attached_buffers) == 3 end)
    assert.truthy(clients()[1].attached_buffers[hidden])
  end)

  it("a new file created under the root is attached too", function()
    local root = project()
    vim.cmd.edit(root .. "/src/a.py")
    wait(function() return #clients() == 1 end)
    vim.fn.writefile({}, root .. "/src/new.py")
    local buf = vim.fn.bufadd(root .. "/src/new.py")
    vim.fn.bufload(buf)
    wait(function() return clients()[1].attached_buffers[buf] end)
  end)

  -- conjure lands a new file as CreateFile with ignoreIfExists, which Neovim answers with only
  -- a buffer (no file on disk) in a folder that may not exist yet: conjure must see that
  -- buffer, or the change counts as not landed and offers no Undo
  it("a file a server's edit creates is attached before it is on disk", function()
    local root = project()
    vim.cmd.edit(root .. "/src/a.py")
    wait(function() return #clients() == 1 end)
    local new = root .. "/src/ports/log/mod.rs"
    local uri = vim.uri_from_fname(new)
    vim.lsp.util.apply_workspace_edit({
      documentChanges = {
        { kind = "create", uri = uri, options = { ignoreIfExists = true } },
        {
          textDocument = { uri = uri, version = vim.NIL },
          edits = { { range = { start = { line = 0, character = 0 }, ["end"] = { line = 1, character = 0 } }, newText = "pub mod log;\n" } },
        },
      },
    }, "utf-16")
    assert.is_nil(vim.uv.fs_stat(new))
    local buf = vim.fn.bufnr(new)
    wait(function() return clients()[1].attached_buffers[buf] end)
  end)

  it("does not attach to a buffer of another scheme", function()
    local root = project()
    vim.cmd.edit(root .. "/src/a.py")
    wait(function() return #clients() == 1 end)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, "fugitive://" .. root .. "/.git//0/src/a.py")
    vim.api.nvim_set_current_buf(buf)
    vim.wait(300)
    assert.is_nil(clients()[1].attached_buffers[buf])
  end)

  it("does not attach to a nofile buffer or outside any root", function()
    vim.cmd.enew()
    vim.bo.buftype = "nofile"
    local dir = vim.fn.resolve(vim.fn.tempname())
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ "z" }, dir .. "/loose.txt")
    vim.cmd.edit(dir .. "/loose.txt")
    vim.wait(300)
    assert.equals(0, #clients())
  end)

  it("status follows conjure's progress and is empty after", function()
    local root = project()
    vim.cmd.edit(root .. "/src/a.py")
    wait(function() return #clients() == 1 end)
    assert.equals("", sorcerer.status())
    progress("conjure", "begin", "conjuring a change")
    assert.equals("conjure: conjuring a change", sorcerer.status())
    progress("conjure", "end")
    assert.equals("", sorcerer.status())
  end)

  it("status joins scry and conjure", function()
    stop_all()
    sorcerer.setup({
      scry = { enabled = true, cmd = { fake, "lsp" } },
      conjure = { enabled = true, cmd = { fake, "lsp" } },
    })
    local root = project()
    vim.cmd.edit(root .. "/src/a.py")
    wait(function() return #clients() == 1 and #clients("scry") == 1 end)
    progress("scry", "begin", "reviewing 2 units")
    assert.equals("scry: reviewing 2 units", sorcerer.status())
    progress("conjure", "begin", "conjuring a change")
    assert.equals("scry: reviewing 2 units  conjure: conjuring a change", sorcerer.status())
  end)
end)
