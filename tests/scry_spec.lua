-- scry in Neovim: one client a root, started on the files that open, the fake `scry lsp`.
local sorcerer = require("sorcerer")
local fake = vim.fn.fnamemodify("tests/fake-lsp", ":p")

local function wait(pred, ms) assert(vim.wait(ms or 5000, pred, 10), "timed out") end
local function clients() return vim.lsp.get_clients({ name = "scry" }) end
local function read(path)
  local f = io.open(path)
  if not f then return "" end
  local s = f:read("*a")
  f:close()
  return s
end

-- a temp project: marker (".git" or ".sorcerer") at the top, src/a.py and src/b.py
local function project(marker)
  local root = vim.fn.resolve(vim.fn.tempname())
  vim.fn.mkdir(root .. "/" .. marker, "p")
  vim.fn.mkdir(root .. "/src", "p")
  vim.fn.writefile({ "def f(x):", "    return x + 2", "" }, root .. "/src/a.py")
  vim.fn.writefile({ "x = 1" }, root .. "/src/b.py")
  return root
end

local function stop_all()
  for _, c in ipairs(clients()) do c:stop(true) end
  wait(function() return #clients() == 0 end)
end

describe("sorcerer.scry", function()
  local replies
  before_each(function()
    stop_all()
    vim.cmd("silent! %bwipeout!")
    vim.env.FAKE_LSP_LOG = vim.fn.tempname()
    replies = vim.fn.tempname()
    vim.fn.mkdir(replies, "p")
    vim.env.FAKE_LSP_REPLIES = replies
    sorcerer.setup({ scry = { cmd = { fake, "lsp" } } })
  end)

  it("attaches to a file under .git", function()
    local root = project(".git")
    vim.cmd.edit(root .. "/src/a.py")
    wait(function() return #clients() == 1 end)
    assert.equals(root, clients()[1].config.root_dir)
  end)

  it("prefers the .sorcerer directory above a nearer .git", function()
    local root = project(".sorcerer")
    vim.fn.mkdir(root .. "/src/.git", "p")
    vim.fn.writefile({ "y = 2" }, root .. "/src/c.py")
    vim.cmd.edit(root .. "/src/c.py")
    wait(function() return #clients() == 1 end)
    assert.equals(root, clients()[1].config.root_dir)
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

  it("enabled = false starts nothing", function()
    sorcerer.setup({ scry = { enabled = false, cmd = { fake, "lsp" } } })
    local root = project(".git")
    vim.cmd.edit(root .. "/src/a.py")
    vim.wait(300)
    assert.equals(0, #clients())
  end)

  it("two buffers of one root share one client", function()
    local root = project(".git")
    vim.cmd.edit(root .. "/src/a.py")
    vim.cmd.edit(root .. "/src/b.py")
    wait(function() return #clients() == 1 and vim.tbl_count(clients()[1].attached_buffers) == 2 end)
    assert.equals(1, #clients())
  end)

  it("a save draws the fake server's bug with its sign and line-end sentence", function()
    local root = project(".git")
    vim.fn.writefile({ vim.json.encode({ { line = 1, code = "bug", statement = "f adds two, not one. The caller expects one.", rule = "r1", id = "f1", evidence = "src/a.py:2" } }) }, replies .. "/diagnostics.json")
    vim.cmd.edit(root .. "/src/a.py")
    wait(function() return #clients() == 1 and clients()[1].initialized end)
    vim.cmd.write()
    wait(function() return #vim.diagnostic.get(0) == 1 end)
    local d = vim.diagnostic.get(0)[1]
    assert.equals("scry", d.source)
    assert.equals("bug", d.code)
    assert.equals(vim.diagnostic.severity.ERROR, d.severity)
    assert.equals(1, d.lnum)
    local found
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, require("sorcerer.signs").sign_ns, 0, -1, { details = true })) do
      found = found or m
    end
    assert.truthy(found)
    assert.equals(1, found[2])
    assert.equals("!", vim.trim(found[4].sign_text))
    assert.equals("! f adds two, not one.", found[4].virt_text[1][1])
  end)

  it('status is "scry: reviewing 2 units" during a review, follows a report, and is empty after', function()
    local root = project(".git")
    vim.fn.writefile({ vim.json.encode({ report = "reviewing 3 units" }) }, replies .. "/report.json")
    vim.fn.writefile({ "[]" }, replies .. "/diagnostics.json")
    vim.cmd.edit(root .. "/src/a.py")
    wait(function() return #clients() == 1 and clients()[1].initialized end)
    assert.equals("", sorcerer.status())
    local seen = {}
    vim.api.nvim_create_autocmd("LspProgress", { callback = function() table.insert(seen, sorcerer.status()) end })
    vim.cmd.write()
    wait(function() return #seen >= 3 end)
    wait(function() return sorcerer.status() == "" end)
    assert.same({ "scry: reviewing 2 units", "scry: reviewing 3 units", "" }, seen)
  end)
end)
