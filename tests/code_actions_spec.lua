-- The code-action menu: each server's fixes together (preferred first), then the rest.
local code_actions = require("sorcerer.code_actions")

local function item(title, kind, preferred, client_id)
  return { action = { title = title, kind = kind, isPreferred = preferred }, ctx = { client_id = client_id } }
end

local function titles(items)
  return vim.tbl_map(function(one) return one.action.title end, items)
end

local menu = {
  item("Conjure here", "refactor.rewrite"),
  item("Conjure for this finding", "refactor.rewrite"),
  item("spellbook: Use a port", "quickfix", true),
  item("spellbook: Add a port", "quickfix"),
  item("no kind"),
}

describe("sorcerer.code_actions", function()
  local select
  before_each(function() select = vim.ui.select end)
  after_each(function()
    vim.ui.select = select
    code_actions.setup(false)
  end)

  it("orders fixes first and keeps each group's order", function()
    assert.same(
      { "spellbook: Use a port", "spellbook: Add a port", "Conjure here", "Conjure for this finding", "no kind" },
      titles(code_actions.ordered(menu))
    )
  end)

  it("keeps each server's fixes together, its preferred fix first", function()
    -- two servers each with a preferred fix: the second's must not come between the first's
    local two = {
      item("spellbook: Use a port", "quickfix", true, 1),
      item("spellbook: Add a port", "quickfix", nil, 1),
      item("Conjure here", "refactor.rewrite", nil, 2),
      item("Ruff (I001): Organize imports", "quickfix", true, 3),
      item("Ruff (I001): Disable for this line", "quickfix", nil, 3),
      item("Ruff: Fix all", "source.fixAll", nil, 3),
    }
    assert.same({
      "spellbook: Use a port", "spellbook: Add a port",
      "Ruff (I001): Organize imports", "Ruff (I001): Disable for this line",
      "Conjure here", "Ruff: Fix all",
    }, titles(code_actions.ordered(two)))
  end)

  it("puts a server with no preferred fix after those with one", function()
    local two = {
      item("lint: Disable", "quickfix", nil, 3),
      item("spellbook: Add a port", "quickfix", nil, 1),
      item("spellbook: Use a port", "quickfix", true, 1),
    }
    assert.same(
      { "spellbook: Use a port", "spellbook: Add a port", "lint: Disable" },
      titles(code_actions.ordered(two))
    )
  end)

  it("reorders the code-action menu only, and wraps again when a server attaches", function()
    local offered
    vim.ui.select = function(items) offered = items end
    code_actions.setup(true)
    vim.ui.select(menu, { kind = "codeaction" }, function() end)
    assert.equals("spellbook: Use a port", offered[1].action.title)
    vim.ui.select(menu, { prompt = "pick" }, function() end)
    assert.equals("Conjure here", offered[1].action.title)

    -- a picker set up later replaces select; the next attach wraps it
    vim.ui.select = function(items) offered = items end
    vim.api.nvim_exec_autocmds("LspAttach", { data = { client_id = 0 } })
    vim.ui.select(menu, { kind = "codeaction" }, function() end)
    assert.equals("spellbook: Use a port", offered[1].action.title)
    local wrapped = vim.ui.select
    vim.api.nvim_exec_autocmds("LspAttach", { data = { client_id = 0 } })
    assert.equals(wrapped, vim.ui.select)
  end)

  it("leaves the menu alone when off", function()
    local plain = function() end
    vim.ui.select = plain
    code_actions.setup(false)
    vim.api.nvim_exec_autocmds("LspAttach", { data = { client_id = 0 } })
    assert.equals(plain, vim.ui.select)
  end)
end)
