-- The code-action menu: preferred quick fixes first, then quick fixes, then the rest.
local code_actions = require("sorcerer.code_actions")

local function item(title, kind, preferred)
  return { action = { title = title, kind = kind, isPreferred = preferred }, ctx = {} }
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
