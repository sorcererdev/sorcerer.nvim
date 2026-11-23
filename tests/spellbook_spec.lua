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

-- ---- :Spellbook new ----

local MAIN = "src/bistro/booking/commands/cancel_table.py"
local TEST = "src/bistro/booking/commands/cancel_table__test.py"

-- write the fake server's canned replies, name -> table, into a fresh directory
local function replies(canned)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  for name, value in pairs(canned) do
    vim.fn.writefile({ vim.json.encode(value) }, dir .. "/workspace_executeCommand_" .. name .. ".json")
  end
  vim.env.FAKE_LSP_REPLIES = dir
end

local generators = {
  {
    id = "command", name = "Command", summary = "A command of a service, with its test",
    inputs = {
      { name = "app", type = "enum", prompt = "The app", optional = false },
      { name = "service", type = "enum", prompt = "The service", optional = false },
      { name = "command", type = "ident", prompt = "The command", optional = false },
    },
  },
}

local plan = {
  id = "ab12cd34", generator = "command", inputs = {},
  files = {
    { path = "src/bistro/booking/commands/__init__.py", status = "skipped", text = "", lines = 0 },
    { path = MAIN, status = "new", text = "def a():\n    pass\n\n\nraise NotImplementedError\n", lines = 5 },
    { path = TEST, status = "new", text = "def t():\n    pass\n", lines = 2 },
  },
  holes = {
    { name = "handle", kind = "block", instruction = "its first case", source = "placeholder", places = { { file = MAIN, line = 5 } } },
    { name = "purpose", kind = "text", instruction = "x", source = "derived", places = { { file = MAIN, line = 1 } } },
  },
}

local applied = {
  written = { "src/a.py", TEST }, skipped = {}, holes = plan.holes,
  first = { file = "src/a.py", line = 2 },
}

-- the scripted pickers: ANSWERS is consumed in order; a number picks that item of a select, a
-- string is the text of an input, false cancels. Returns the log of what was asked.
local function pickers(answers)
  local asked = { select = {}, input = {} }
  local function next_answer() return table.remove(answers, 1) end
  vim.ui.select = function(items, o, cb)
    table.insert(asked.select, { items = items, prompt = o.prompt, o = o })
    local a = next_answer()
    cb(a and items[a] or nil, a or nil)
  end
  vim.ui.input = function(o, cb)
    table.insert(asked.input, o.prompt)
    local a = next_answer()
    cb(a or nil)
  end
  return asked
end

-- the executeCommand messages the fake logged for COMMAND, in order
local function logged(log, name)
  local found = {}
  if vim.fn.filereadable(log) == 0 then return found end
  for _, line in ipairs(vim.fn.readfile(log)) do
    local msg = vim.json.decode(line)
    if msg.method == "workspace/executeCommand" and msg.params.command == name then table.insert(found, msg.params.arguments) end
  end
  return found
end

local function float()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then return win, vim.api.nvim_win_get_buf(win) end
  end
end

local function press(buf, key)
  vim.api.nvim_buf_call(buf, function() vim.fn.maparg(key, "n", false, true).callback() end)
end

local function close_floats()
  local win = float()
  if win then vim.api.nvim_win_close(win, true) end
end

describe("sorcerer.spellbook :Spellbook new", function()
  local root, log, messages, notify

  before_each(function()
    stop_all()
    close_floats()
    vim.cmd("silent! %bwipeout!")
    log = vim.fn.tempname()
    vim.env.FAKE_LSP_LOG = log
    vim.env.FAKE_LSP_NAME = "spellbook"
    require("sorcerer.spellbook").show_wait_ms = 50
    root = project()
    messages, notify = {}, vim.notify
    vim.notify = function(msg) table.insert(messages, msg) end
  end)

  after_each(function()
    vim.notify = notify
    vim.env.FAKE_LSP_NAME = nil
    vim.env.FAKE_LSP_REPLIES = nil
    close_floats()
  end)

  -- the fake reads its replies when it starts, so the server starts after they are written
  local function start(canned)
    replies(canned)
    sorcerer.setup({ scry = { enabled = false }, spellbook = { enabled = true, cmd = { fake, "lsp" } } })
    vim.cmd.edit(root .. "/src/b.py")
    wait(function() return #clients() == 1 and clients()[1].initialized end)
  end

  local function canned_all()
    start({
      ["spellbook.generators"] = generators,
      ["spellbook.choices_app"] = { choices = { "bistro" } },
      ["spellbook.choices_service"] = { choices = { "booking", "kitchen" } },
      ["spellbook.plan"] = plan,
      ["spellbook.apply"] = applied,
    })
  end

  it("new picks a generator, asks the inputs and shows the plan", function()
    canned_all()
    local asked = pickers({ 1, 1, "cancel_table" })
    vim.cmd("Spellbook new")
    local win, buf = nil, nil
    wait(function() win, buf = float(); return win ~= nil end)
    -- the generator, then the service; the app had one choice, taken silently
    assert.equals(2, #asked.select)
    assert.equals("Command — A command of a service, with its test", asked.select[1].o.format_item(generators[1]))
    assert.same({ "booking", "kitchen" }, asked.select[2].items)
    assert.same({ "The command: " }, asked.input)
    local planned = logged(log, "spellbook.plan")
    assert.same({ "command", { app = "bistro", service = "booking", command = "cancel_table" } }, planned[1])
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("= src/bistro/booking/commands/__init__.py (exists, skipped)", lines[1])
    assert.equals("+ " .. MAIN .. " (5 lines)", lines[2])
    assert.equals("1 hole to fill", lines[4])
    assert.truthy(vim.tbl_contains(lines, "── " .. MAIN .. " ──"))
    -- the hole's line is lit
    local lit = vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })
    assert.equals(1, #lit)
    assert.equals("raise NotImplementedError", lines[lit[1][2] + 1])
  end)

  it("given inputs are not asked", function()
    canned_all()
    local asked = pickers({})
    vim.cmd("Spellbook new command service=booking command=cancel_table")
    wait(function() return float() ~= nil end)
    assert.equals(0, #asked.select)
    assert.equals(0, #asked.input)
    assert.equals(0, #logged(log, "spellbook.choices") - 1) -- only app was asked of the server
  end)

  it("an input with one choice is taken without asking", function()
    canned_all()
    local asked = pickers({ 1, "cancel_table" })
    vim.cmd("Spellbook new command")
    wait(function() return float() ~= nil end)
    assert.equals(1, #asked.select) -- the service only
    assert.equals("The service", asked.select[1].prompt)
  end)

  it("a stop is said and ends the flow", function()
    start({
      ["spellbook.generators"] = generators,
      ["spellbook.choices_app"] = { stop = "no apps here" },
    })
    pickers({})
    vim.cmd("Spellbook new command")
    wait(function() return #messages > 0 end)
    assert.equals("no apps here", messages[1])
    vim.wait(100)
    assert.is_nil(float())
    assert.equals(0, #logged(log, "spellbook.plan"))
  end)

  it("a plan that stops on an input asks that input again once", function()
    start({
      ["spellbook.generators"] = generators,
      ["spellbook.choices_app"] = { choices = { "bistro" } },
      ["spellbook.plan"] = { stop = "service must be one of booking", input = "service", choices = { "booking" } },
    })
    local asked = pickers({ 1 })
    vim.cmd("Spellbook new command service=kitchen command=x")
    wait(function() return #logged(log, "spellbook.plan") == 2 end)
    assert.equals("The service", asked.select[1].prompt)
    assert.equals("booking", logged(log, "spellbook.plan")[2][2].service)
  end)

  it("<CR> in the plan applies and q cancels", function()
    canned_all()
    pickers({})
    vim.cmd("Spellbook new command service=booking command=cancel_table")
    local buf
    wait(function() local w, b = float(); buf = b; return w ~= nil end)
    press(buf, "q")
    assert.is_nil(float())
    vim.wait(100)
    assert.equals(0, #logged(log, "spellbook.apply"))
    vim.cmd("Spellbook new command service=booking command=cancel_table")
    wait(function() local w, b = float(); buf = b; return w ~= nil end)
    press(buf, "<CR>")
    wait(function() return #logged(log, "spellbook.apply") == 1 end)
    assert.same({ "ab12cd34" }, logged(log, "spellbook.apply")[1])
    assert.is_nil(float())
    -- the first hole's file is opened when the server did not show it, and the end line says so
    wait(function() return #messages > 0 end)
    assert.equals(root .. "/src/a.py", vim.api.nvim_buf_get_name(0))
    assert.equals(2, vim.api.nvim_win_get_cursor(0)[1])
    assert.equals("spellbook: wrote 2 files · 1 holes, marked; ]d walks them", messages[#messages])
  end)

  local function with_conjure(conjure_holes)
    stop_all()
    sorcerer.setup({
      scry = { enabled = false },
      spellbook = { enabled = true, cmd = { fake, "lsp" }, conjure_holes = conjure_holes },
    })
    vim.cmd.edit(root .. "/src/b.py")
    wait(function() return #clients() == 1 end)
    -- a second fake, named conjure, with its own log
    local conjure_log = vim.fn.tempname()
    vim.env.FAKE_LSP_LOG, vim.env.FAKE_LSP_NAME = conjure_log, "conjure"
    vim.lsp.start({ name = "conjure", cmd = { fake, "lsp" }, root_dir = root }, { bufnr = 0 })
    vim.env.FAKE_LSP_LOG, vim.env.FAKE_LSP_NAME = log, "spellbook"
    wait(function() return #clients("conjure") == 1 and clients("conjure")[1].initialized end)
    return conjure_log
  end

  it("the end line names <leader>ca when conjure is attached", function()
    canned_all()
    local conjure_log = with_conjure(false)
    pickers({})
    vim.cmd("Spellbook new command service=booking command=cancel_table")
    local buf
    wait(function() local w, b = float(); buf = b; return w ~= nil end)
    press(buf, "<CR>")
    wait(function() return #messages > 0 end)
    assert.equals("spellbook: wrote 2 files · 1 holes · <leader>ca to conjure the first", messages[#messages])
    vim.wait(100)
    assert.equals(0, #logged(conjure_log, "conjure.conjure"))
  end)

  it("conjure_holes runs conjure.conjure on the first hole", function()
    canned_all()
    local conjure_log = with_conjure(true)
    pickers({})
    vim.cmd("Spellbook new command service=booking command=cancel_table")
    local buf
    wait(function() local w, b = float(); buf = b; return w ~= nil end)
    press(buf, "<CR>")
    wait(function() return #logged(conjure_log, "conjure.conjure") == 1 end)
    assert.same({ vim.uri_from_fname(root .. "/src/a.py"), 2 }, logged(conjure_log, "conjure.conjure")[1])
  end)

  it("with no spellbook client it says to open a file in the project", function()
    stop_all()
    vim.cmd("silent! %bwipeout!")
    vim.cmd("Spellbook new")
    assert.equals("spellbook: open a file in the project first", messages[1])
  end)
end)
