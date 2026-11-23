-- spellbook in Neovim: opt-in, one client a root named `spellbook`, attached to every buffer
-- under the root; the fake `spellbook lsp`.
local sorcerer = require("sorcerer")
local fake = vim.fn.fnamemodify("tests/fake-lsp", ":p")

local function wait(pred, ms) assert(vim.wait(ms or 5000, pred, 10), "timed out") end
local function clients(name) return vim.lsp.get_clients({ name = name or "spellbook" }) end

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
  for _, name in ipairs({ "spellbook", "conjure", "scry" }) do
    for _, c in ipairs(clients(name)) do c:stop(true) end
  end
  wait(function() return #clients() == 0 and #clients("conjure") == 0 and #clients("scry") == 0 end)
end

describe("sorcerer.spellbook", function()
  before_each(function()
    stop_all()
    vim.cmd("silent! %bwipeout!")
    vim.env.FAKE_LSP_LOG = vim.fn.tempname()
    vim.env.FAKE_LSP_NAME = "spellbook"
    sorcerer.setup({ scry = { enabled = false }, spellbook = { enabled = true, cmd = { fake, "lsp" } } })
  end)

  after_each(function() vim.env.FAKE_LSP_NAME = nil end)

  it("spellbook starts on a root when enabled", function()
    local root = project()
    vim.cmd.edit(root .. "/src/a.py")
    wait(function() return #clients() == 1 end)
    assert.equals(root, clients()[1].config.root_dir)
    assert.equals(0, #clients("scry"))
    assert.equals(0, #clients("conjure"))
  end)

  it("spellbook stays off by default", function()
    stop_all()
    sorcerer.setup({ scry = { enabled = false, cmd = { fake, "lsp" } } })
    local root = project()
    vim.cmd.edit(root .. "/src/a.py")
    vim.wait(300)
    assert.equals(0, #clients())
    local defaults = require("sorcerer").defaults.spellbook
    assert.is_false(defaults.enabled)
    assert.is_false(defaults.conjure_holes)
    assert.same({ "spellbook", "lsp" }, defaults.cmd)
  end)

  it("spellbook attaches to every buffer under the root, so it sees each save", function()
    local root = project()
    vim.cmd.edit(root .. "/src/a.py")
    vim.cmd.edit(root .. "/notes.txt")
    wait(function() return #clients() == 1 and vim.tbl_count(clients()[1].attached_buffers) == 2 end)
  end)

  it("a missing spellbook warns once, naming the setting", function()
    stop_all()
    local warnings = {}
    local notify = vim.notify
    vim.notify = function(msg, level) table.insert(warnings, { msg, level }) end
    sorcerer.setup({ scry = { enabled = false }, spellbook = { enabled = true, cmd = { "no-such-spellbook", "lsp" } } })
    local root = project()
    vim.cmd.edit(root .. "/src/a.py")
    vim.cmd.edit(root .. "/src/b.py")
    vim.wait(200)
    vim.notify = notify
    assert.equals(1, #warnings)
    assert.truthy(warnings[1][1]:find("spellbook.cmd", 1, true))
    assert.equals(0, #clients())
  end)
end)
