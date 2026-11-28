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
  for _, one in ipairs(keys.table_of_keys) do
    for _, mode in ipairs({ "n", "v" }) do pcall(vim.keymap.del, mode, "<leader>m" .. one.key) end
  end
  for _, key in ipairs({ "c", "conjure" }) do pcall(vim.keymap.del, "n", "<leader>m" .. key) end
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

  it("binds the common keys and each product's group under <leader>m", function()
    sorcerer.setup(both)
    -- common: f fix this, g generate, n next step, u undo the last change
    for _, key in ipairs({ "f", "g", "n", "u", "cn", "ct", "cu", "cw", "bg", "bf", "bk", "bs", "bh" }) do
      assert.is_true(bound("<leader>m" .. key), key)
    end
    assert.is_true(bound("<leader>mn", "v"))
    assert.is_true(bound("<leader>mcn", "v"))
    assert.equals("<leader>mn", keys.lhs("next_step"))
    assert.equals("<leader>mbs", keys.lhs("spellbook_sync"))
    assert.equals("<leader>mct", keys.lhs("conjure_try_again"))
    assert.equals(13, #keys.bound())
    -- no key is said "sorcerer: …"; the descriptions are plain
    assert.equals("try the change again with more effort", vim.fn.maparg("<leader>mct", "n", false, true).desc)
    assert.equals("generate…", vim.fn.maparg("<leader>mg", "n", false, true).desc)
    for _, one in ipairs(keys.table_of_keys) do assert.is_nil(one.desc:find("sorcerer"), one.name) end
  end)

  it("every key has its own lhs, and the scry and lackey keys follow the layout", function()
    local seen = {}
    for _, one in ipairs(keys.table_of_keys) do
      assert.is_nil(seen[one.key], one.key)
      seen[one.key] = one.name
    end
    local d = keys.defaults()
    assert.same({ "a", "f", "g", "n", "u", "w", "q" }, { d["do"], d.fix, d.generate, d.next_step, d.undo, d.why, d.stop })
    assert.same({ "sw", "sr", "sx", "sl" }, { d.scry_why, d.scry_review, d.scry_dismiss, d.scry_list })
    assert.same({ "la", "lq", "ld", "lz", "lj", "lo", "lx", "ll" },
      { d.lackey_do, d.lackey_stop, d.lackey_diff, d.lackey_undo, d.lackey_journal, d.lackey_open_answer, d.lackey_dismiss, d.lackey_label })
  end)

  it("binds only the tools that are on", function()
    sorcerer.setup({ scry = { enabled = false } })
    assert.same({}, keys.bound())
    sorcerer.setup({ scry = { enabled = false }, conjure = { enabled = true, cmd = { fake, "lsp" } } })
    assert.is_true(bound("<leader>mu"))
    assert.is_true(bound("<leader>mcu"))
    assert.is_false(bound("<leader>mg"))
    assert.is_nil(keys.lhs("spellbook_check"))
  end)

  it("keys = false binds none", function()
    sorcerer.setup(vim.tbl_extend("force", both, { keys = false }))
    assert.same({}, keys.bound())
    assert.is_false(bound("<leader>mn"))
  end)

  it("one key set to false is skipped; the prefix can change", function()
    sorcerer.setup(vim.tbl_extend("force", both, { keys = { undo = false, prefix = "<leader>m" } }))
    assert.is_false(bound("<leader>mu"))
    assert.is_true(bound("<leader>mn"))
  end)

  it("an old key name is reported, not bound", function()
    sorcerer.setup(vim.tbl_extend("force", both, { keys = { try_harder = "t" } }))
    assert.same({ "try_harder" }, keys.unknown())
    assert.is_false(bound("<leader>mt"))
  end)

  it("a key you already mapped is skipped and reported, never overwritten", function()
    vim.keymap.set("n", "<leader>mn", "<cmd>echo 'mine'<cr>")
    sorcerer.setup(both)
    assert.equals("<cmd>echo 'mine'<cr>", vim.fn.maparg("<leader>mn", "n", false, true).rhs)
    assert.same({ { name = "next_step", lhs = "<leader>mn" } }, keys.skipped())
    assert.is_nil(keys.lhs("next_step"))
    assert.equals("<leader>mcn", keys.conjure_lhs())
    -- a second setup keeps our own maps and still leaves the user's
    sorcerer.setup(both)
    assert.is_true(bound("<leader>mu"))
    assert.equals("<cmd>echo 'mine'<cr>", vim.fn.maparg("<leader>mn", "n", false, true).rhs)
  end)

  it("which-key, when installed, names each prefix after its product", function()
    local added
    package.loaded["which-key"] = { add = function(spec) added = spec end }
    sorcerer.setup(both)
    package.loaded["which-key"] = nil
    local names = {}
    for _, g in ipairs(added) do names[g[1]] = g.group end
    assert.same({ ["<leader>m"] = "sorcerer", ["<leader>mc"] = "conjure", ["<leader>mb"] = "spellbook" }, names)
  end)

  it("<leader>mcu applies only the `conjure: Undo` action", function()
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
    vim.fn.maparg("<leader>mcu", "n", false, true).callback()
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

  describe("undo the last change (<leader>mu)", function()
    local last = require("sorcerer.last_change")
    before_each(function()
      stop_all()
      unmap_all()
      vim.env.FAKE_LSP_LOG = vim.fn.tempname()
      vim.env.FAKE_LSP_NAME = "conjure"
    end)
    local function edit_at(uri, line)
      return { changes = { [uri] = { { range = { start = { line = line, character = 0 }, ["end"] = { line = line, character = 0 } }, newText = "x" } } } }
    end

    it("remembers each writer's edits, the latest last, and one lackey task as one change", function()
      last.forget()
      local uri = vim.uri_from_fname(vim.fn.tempname() .. ".py")
      last.record("conjure", edit_at(uri, 4))
      last.record("lackey", edit_at(uri, 1))
      last.record("lackey", edit_at(uri, 9))
      last.record("scry", edit_at(uri, 2))
      local change = last.last()
      assert.equals("lackey", change.tool)
      assert.equals(2, #change.at)
      assert.equals(1, change.at[1].row)
    end)

    it("with nothing changed, says so", function()
      last.forget()
      local said
      local real = vim.notify
      vim.notify = function(msg) said = msg end
      last.undo()
      vim.notify = real
      assert.truthy(said:find("nothing to undo", 1, true), said)
    end)

    it("undoes conjure's change through conjure's own Undo, says whose, and forgets it", function()
      local log = vim.env.FAKE_LSP_LOG
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      vim.fn.writefile({ vim.json.encode({
        { title = "conjure: Undo", command = { title = "conjure: Undo", command = "conjure.undo", arguments = { "c1" } } },
        { title = "conjure: Show why", command = { title = "conjure: Show why", command = "conjure.why", arguments = { "c1" } } },
      }) }, dir .. "/textDocument_codeAction.json")
      vim.env.FAKE_LSP_REPLIES = dir
      sorcerer.setup({ scry = { enabled = false }, conjure = { enabled = true, cmd = { fake, "lsp" } } })
      local root = project()
      vim.cmd.edit(root .. "/src/a.py")
      -- conjure attaches to every loaded buffer, so an earlier test's buffer has its own client
      wait(function()
        local here = vim.lsp.get_clients({ bufnr = 0, name = "conjure" })[1]
        return here ~= nil and here.initialized
      end)
      local buf = vim.api.nvim_get_current_buf()
      last.forget()
      last.record("conjure", edit_at(vim.uri_from_bufnr(buf), 1))
      local ns = vim.api.nvim_create_namespace("test_conjure_marks")
      local lsp = { range = { start = { line = 1, character = 0 }, ["end"] = { line = 1, character = 8 } }, source = "conjure", code = "change", message = "conjured: x", data = "c1" }
      vim.diagnostic.set(ns, buf, { { lnum = 1, col = 0, source = "conjure", code = "change", message = "conjured: x", user_data = { lsp = lsp } } })
      local said = {}
      local real = vim.notify
      vim.notify = function(msg) table.insert(said, msg) end
      vim.fn.maparg("<leader>mu", "n", false, true).callback()
      local function executed()
        local found = {}
        for _, line in ipairs(vim.fn.readfile(log)) do
          local msg = vim.json.decode(line)
          if msg.method == "workspace/executeCommand" then table.insert(found, msg.params.command) end
        end
        return found
      end
      local ok = vim.wait(5000, function() return #executed() >= 1 end, 10)
      assert.is_true(ok, vim.inspect(said))
      vim.fn.maparg("<leader>mu", "n", false, true).callback()
      vim.notify = real
      vim.diagnostic.reset(ns, buf)
      assert.same({ "conjure.undo" }, executed())
      assert.equals("undo: conjure's last change (a.py:2)", said[1])
      assert.truthy(said[2]:find("nothing to undo", 1, true), said[2])
    end)
  end)
end)
