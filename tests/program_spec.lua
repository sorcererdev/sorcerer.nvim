-- A missing program: one warning each, no client, however many buffers open.
local sorcerer = require("sorcerer")

local function project()
  local root = vim.fn.resolve(vim.fn.tempname())
  vim.fn.mkdir(root .. "/.git", "p")
  for _, name in ipairs({ "a.py", "b.py", "c.py" }) do vim.fn.writefile({ "x = 1" }, root .. "/" .. name) end
  return root
end

describe("a missing program", function()
  local warnings, notify
  before_each(function()
    vim.cmd("silent! %bwipeout!")
    warnings = {}
    notify = vim.notify
    vim.notify = function(msg, level) table.insert(warnings, { msg = msg, level = level }) end
  end)
  after_each(function() vim.notify = notify end)

  it("warns once per program and starts no client", function()
    sorcerer.setup({
      scry = { cmd = { "sorcerer-no-such-scry", "lsp" } },
      conjure = { enabled = true, cmd = { "sorcerer-no-such-conjure", "lsp" } },
    })
    local root = project()
    for _, name in ipairs({ "a.py", "b.py", "c.py" }) do vim.cmd.edit(root .. "/" .. name) end
    vim.wait(300)
    assert.equals(0, #vim.lsp.get_clients())
    assert.equals(2, #warnings)
    assert.equals(vim.log.levels.WARN, warnings[1].level)
    local both = warnings[1].msg .. warnings[2].msg
    assert.truthy(both:find("`sorcerer-no-such-scry` is not on the path", 1, true))
    assert.truthy(both:find("scry.cmd", 1, true))
    assert.truthy(both:find("sorcerer-scry-installer", 1, true))
    assert.truthy(both:find("conjure.cmd", 1, true))
    assert.truthy(both:find("sorcerer-conjure-installer", 1, true))
  end)
end)
