-- sorcerer's keys under <leader>m: bound when the tool is on, never over a key you mapped.
local sorcerer = require("sorcerer")
local keys = require("sorcerer.keys")
local fake = vim.fn.fnamemodify("tests/fake-lsp", ":p")

local function wait(pred, ms) assert(vim.wait(ms or 5000, pred, 10), "timed out") end
local function clients(name) return vim.lsp.get_clients({ name = name }) end
local function bound(lhs, mode) return vim.fn.maparg(lhs, mode or "n") ~= "" end

local function project()
  local root = vim.fn.resolve(vim.fn.tempname())
  vim.fn.mkdir(root .. "/.git", "p")
  vim.fn.mkdir(root .. "/src", "p")
  vim.fn.writefile({ "def f(x):", "    pass", "" }, root .. "/src/a.py")
  return root
end

local function stop_all()
  for _, name in ipairs({ "spellbook", "conjure", "scry" }) do
    for _, c in ipairs(clients(name)) do c:stop(true) end
  end
  wait(function() return #clients("spellbook") + #clients("conjure") + #clients("scry") == 0 end)
end

local function unmap_all()
  for _, key in ipairs({ "n", "f", "c", "u", "t", "w", "k", "x" }) do
    for _, mode in ipairs({ "n", "v" }) do pcall(vim.keymap.del, mode, "<leader>m" .. key) end
  end
end

local both = { scry = { enabled = false }, conjure = { enabled = true, cmd = { fake, "lsp" } }, spellbook = { enabled = true, cmd = { fake, "lsp" } } }

describe("sorcerer.keys", function()
  before_each(function()
    stop_all()
    unmap_all()
    vim.env.FAKE_LSP_LOG = vim.fn.tempname()
    vim.env.FAKE_LSP_NAME = "conjure"
  end)
  after_each(function()
    vim.env.FAKE_LSP_NAME, vim.env.FAKE_LSP_REPLIES = nil, nil
    unmap_all()
  end)

  it("binds seven maps under <leader>m when both tools are on", function()
    sorcerer.setup(both)
    for _, key in ipairs({ "n", "f", "c", "u", "t", "w", "k" }) do assert.is_true(bound("<leader>m" .. key), key) end
    assert.is_true(bound("<leader>mc", "v"))
    assert.equals("<leader>mc", keys.lhs("conjure"))
    assert.equals(7, #keys.bound())
  end)

  it("binds only the tools that are on", function()
    sorcerer.setup({ scry = { enabled = false } })
    assert.same({}, keys.bound())
    sorcerer.setup({ scry = { enabled = false }, conjure = { enabled = true, cmd = { fake, "lsp" } } })
    assert.is_true(bound("<leader>mu"))
    assert.is_false(bound("<leader>mn"))
    assert.is_nil(keys.lhs("check"))
  end)

  it("keys = false binds none", function()
    sorcerer.setup(vim.tbl_extend("force", both, { keys = false }))
    assert.same({}, keys.bound())
    assert.is_false(bound("<leader>mc"))
  end)

  it("one key set to false is skipped; the prefix can change", function()
    sorcerer.setup(vim.tbl_extend("force", both, { keys = { undo = false, prefix = "<leader>m" } }))
    assert.is_false(bound("<leader>mu"))
    assert.is_true(bound("<leader>mc"))
  end)

  it("a key you already mapped is skipped and reported, never overwritten", function()
    vim.keymap.set("n", "<leader>mc", "<cmd>echo 'mine'<cr>")
    sorcerer.setup(both)
    assert.equals("<cmd>echo 'mine'<cr>", vim.fn.maparg("<leader>mc", "n", false, true).rhs)
    assert.same({ { name = "conjure", lhs = "<leader>mc" } }, keys.skipped())
    assert.is_nil(keys.lhs("conjure"))
    -- a second setup keeps our own maps and still leaves the user's
    sorcerer.setup(both)
    assert.is_true(bound("<leader>mu"))
    assert.equals("<cmd>echo 'mine'<cr>", vim.fn.maparg("<leader>mc", "n", false, true).rhs)
  end)

  it("<leader>mu applies only the `conjure: Undo` action", function()
    local log = vim.env.FAKE_LSP_LOG
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ vim.json.encode({
      { title = "Conjure here", command = { title = "Conjure here", command = "conjure.conjure", arguments = {} } },
      { title = "conjure: Undo", command = { title = "conjure: Undo", command = "conjure.undo", arguments = { "c1" } } },
      { title = "conjure: Show why", command = { title = "conjure: Show why", command = "conjure.why", arguments = { "c1" } } },
    }) }, dir .. "/textDocument_codeAction.json")
    vim.env.FAKE_LSP_REPLIES = dir
    -- conjure alone: two fake servers would each offer the actions
    sorcerer.setup({ scry = { enabled = false }, conjure = { enabled = true, cmd = { fake, "lsp" } } })
    local root = project()
    vim.cmd.edit(root .. "/src/a.py")
    wait(function() return #clients("conjure") == 1 and clients("conjure")[1].initialized end)
    wait(function() return vim.tbl_contains(vim.lsp.get_clients({ bufnr = 0 }), clients("conjure")[1]) end)
    vim.fn.maparg("<leader>mu", "n", false, true).callback()
    local function executed()
      local found = {}
      for _, line in ipairs(vim.fn.readfile(log)) do
        local msg = vim.json.decode(line)
        if msg.method == "workspace/executeCommand" then table.insert(found, msg.params.command) end
      end
      return found
    end
    wait(function() return #executed() >= 1 end)
    vim.wait(150)
    assert.same({ "conjure.undo" }, executed())
  end)
end)
