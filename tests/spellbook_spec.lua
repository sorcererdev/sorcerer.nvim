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

  it("a new file's first write is attached and sent as a save, so the server syncs on it", function()
    local root = project()
    vim.cmd.edit(root .. "/src/a.py")
    wait(function() return #clients() == 1 and clients()[1].initialized end)
    vim.cmd.edit(root .. "/src/new.py")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "x = 2" })
    vim.cmd("silent write")
    local uri = vim.uri_from_fname(root .. "/src/new.py")
    local saves = function()
      local n = 0
      for _, line in ipairs(vim.fn.readfile(vim.env.FAKE_LSP_LOG)) do
        local msg = vim.json.decode(line)
        if msg.method == "textDocument/didSave" and msg.params.textDocument.uri == uri then n = n + 1 end
      end
      return n
    end
    wait(function() return saves() == 1 end)
    -- a second write is Neovim's own didSave, once
    vim.cmd("silent write")
    wait(function() return saves() == 2 end)
    vim.wait(200)
    assert.equals(2, saves())
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
    { name = "handle", kind = "block", instruction = "its first case", source = "placeholder", places = { { file = MAIN, line = 5, text = "raise NotImplementedError" } } },
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
    -- the hole's placeholder is lit (its own span, not the line)
    local lit = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
      if m[4].hl_group == "SorcererHolePlaceholder" then table.insert(lit, m) end
    end
    assert.equals(1, #lit)
    assert.equals("raise NotImplementedError", lines[lit[1][2] + 1])
    assert.equals(0, lit[1][3])
    assert.equals(#"raise NotImplementedError", lit[1][4].end_col)
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

  it("an apply with no hole to fill (first = null) still ends with the wrote line", function()
    start({
      ["spellbook.generators"] = generators,
      ["spellbook.choices_app"] = { choices = { "bistro" } },
      ["spellbook.plan"] = plan,
      ["spellbook.apply"] = { written = { "src/a.py" }, skipped = {}, holes = {}, first = vim.NIL },
    })
    pickers({})
    vim.cmd("Spellbook new command service=booking command=cancel_table")
    local buf
    wait(function() local w, b = float(); buf = b; return w ~= nil end)
    press(buf, "<CR>")
    wait(function() return #messages > 0 end)
    assert.equals("spellbook: wrote 1 file", messages[#messages])
  end)

  it("an input named with a dash is an input, not the generator", function()
    canned_all()
    pickers({ 1, "cancel_table" })
    vim.cmd("Spellbook new command my-input=x")
    wait(function() return #logged(log, "spellbook.plan") == 1 end)
    assert.equals("x", logged(log, "spellbook.plan")[1][2]["my-input"])
    -- the flow ends with the plan shown: leaving earlier lets its float open during the next test's setup
    wait(function() return float() ~= nil end)
  end)

  -- a conjure client beside the running spellbook one; the server was started by canned_all
  local function with_conjure(conjure_holes)
    sorcerer.opts.spellbook.conjure_holes = conjure_holes
    -- a second fake, named conjure, with its own log
    local conjure_log = vim.fn.tempname()
    vim.env.FAKE_LSP_LOG, vim.env.FAKE_LSP_NAME = conjure_log, "conjure"
    vim.lsp.start({ name = "conjure", cmd = { fake, "lsp" }, root_dir = root }, { bufnr = 0 })
    vim.env.FAKE_LSP_LOG, vim.env.FAKE_LSP_NAME = log, "spellbook"
    wait(function() return #clients("conjure") == 1 and clients("conjure")[1].initialized end)
    return conjure_log
  end

  it("the end line names <leader>mc when conjure is attached", function()
    canned_all()
    local conjure_log = with_conjure(false)
    require("sorcerer.keys").setup({ keys = sorcerer.opts.keys, conjure = { enabled = true } })
    pickers({})
    vim.cmd("Spellbook new command service=booking command=cancel_table")
    local buf
    wait(function() local w, b = float(); buf = b; return w ~= nil end)
    press(buf, "<CR>")
    wait(function() return #messages > 0 end)
    assert.equals("spellbook: wrote 2 files · 1 holes · <leader>mc to conjure the first", messages[#messages])
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
    assert.truthy(messages[1]:find("open a file in the project first", 1, true))
    assert.truthy(messages[1]:find("spellbook.enabled", 1, true))
  end)
end)

-- ---- the hole session: holes as snippet placeholders ----

local CMD = "src/cmd.py"
local CMD_TEST = "src/cmd__test.py"
local CMD_LINES = {
  "def handle(cmd):",
  "    todo_field = 1",
  "    raise NotImplementedError",
  '    name = "é" + todo_name',
}

-- a protocol range on one line, UTF-16 columns
local function range(line, from, to)
  return { start = { line = line, character = from }, ["end"] = { line = line, character = to } }
end

local stops = {
  { file = CMD, name = "field", kind = "ident", instruction = "its first input", range = range(1, 4, 14) },
  { file = CMD, name = "handle", kind = "block", instruction = "its first case", range = range(2, 4, 29) },
  -- after `é` (two bytes, one UTF-16 unit): UTF-16 17..26 is bytes 18..27
  { file = CMD, name = "name", kind = "ident", instruction = "a name", range = range(3, 17, 26) },
  { file = CMD_TEST, name = "field", kind = "ident", instruction = "its first input", range = range(0, 0, 10) },
}

describe("sorcerer.spellbook hole session", function()
  local root, messages, notify, echoed, echo
  local holes = require("sorcerer.spellbook_holes")

  before_each(function()
    stop_all()
    close_floats()
    vim.cmd("silent! %bwipeout!")
    vim.env.FAKE_LSP_LOG = vim.fn.tempname()
    vim.env.FAKE_LSP_NAME = "spellbook"
    require("sorcerer.spellbook").show_wait_ms = 50
    root = project()
    vim.fn.writefile(CMD_LINES, root .. "/" .. CMD)
    vim.fn.writefile({ "todo_field" }, root .. "/" .. CMD_TEST)
    messages, notify = {}, vim.notify
    vim.notify = function(msg) table.insert(messages, msg) end
    echoed, echo = {}, holes.echo
    holes.echo = function(text) table.insert(echoed, text) end
  end)

  after_each(function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do holes.stop(buf) end
    vim.notify = notify
    holes.echo = echo
    vim.env.FAKE_LSP_NAME = nil
    vim.env.FAKE_LSP_REPLIES = nil
    close_floats()
  end)

  -- run the plan float's apply over a canned reply with STOPS; SETUP is the spellbook table;
  -- REPLY_HOLES the reply's holes (the plan's by default)
  local function apply_with(reply_stops, setup, reply_holes)
    replies({
      ["spellbook.generators"] = generators,
      ["spellbook.choices_app"] = { choices = { "bistro" } },
      ["spellbook.plan"] = plan,
      ["spellbook.apply"] = {
        written = { CMD, CMD_TEST }, skipped = {}, holes = reply_holes or plan.holes,
        first = { file = CMD, line = 2 }, stops = reply_stops,
      },
    })
    sorcerer.setup({ scry = { enabled = false }, spellbook = vim.tbl_extend("force", { enabled = true, cmd = { fake, "lsp" } }, setup or {}) })
    vim.cmd.edit(root .. "/src/b.py")
    wait(function() return #clients() == 1 and clients()[1].initialized end)
    pickers({})
    vim.cmd("Spellbook new command service=booking command=cancel_table")
    local buf
    wait(function() local w, b = float(); buf = b; return w ~= nil end)
    press(buf, "<CR>")
  end

  -- run what is waiting in typeahead, staying in the mode it ends in (select or normal)
  local function flush() vim.api.nvim_feedkeys("", "x!", false) end
  local function type_keys(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "mx!", false)
  end
  -- the selected text: from the visual start to the cursor (inclusive), one line
  local function selected()
    local v, c = vim.fn.getpos("v"), vim.fn.getpos(".")
    assert.equals(v[2], c[2])
    local from, to = math.min(v[3], c[3]), math.max(v[3], c[3])
    return vim.api.nvim_get_current_line():sub(from, to)
  end

  it("after apply the first placeholder is selected in select mode, with its message", function()
    apply_with(stops)
    wait(function() return holes.active(vim.api.nvim_get_current_buf()) end)
    flush()
    assert.equals(root .. "/" .. CMD, vim.api.nvim_buf_get_name(0))
    assert.equals("s", vim.fn.mode())
    assert.equals("todo_field", selected())
    assert.equals("hole 1 of 3 · field: its first input · type to replace · <Tab> next", echoed[#echoed])
  end)

  it("the end line is said when the session starts, before the hole's message", function()
    apply_with(stops)
    wait(function() return holes.active(vim.api.nvim_get_current_buf()) end)
    flush()
    assert.same({ "spellbook: wrote 2 files" }, messages)
    assert.truthy(echoed[#echoed]:find("^hole 1 of 3"))
  end)

  it("a reply whose plan has no hole to fill starts no session, whatever its stops", function()
    apply_with(stops, nil, {})
    wait(function() return #messages > 0 end)
    flush()
    assert.is_false(holes.active(vim.api.nvim_get_current_buf()))
    assert.equals("n", vim.fn.mode())
    assert.equals("spellbook: wrote 2 files", messages[#messages])
  end)

  it("typing replaces the placeholder, <Tab> and <S-Tab> move between holes", function()
    apply_with(stops)
    wait(function() return holes.active(vim.api.nvim_get_current_buf()) end)
    flush()
    -- typed in one go: a run that ends in insert mode would wait for more keys
    type_keys("id<Tab>")
    assert.equals("    id = 1", vim.api.nvim_buf_get_lines(0, 1, 2, false)[1])
    assert.equals("s", vim.fn.mode())
    assert.equals("raise NotImplementedError", selected())
    assert.equals("hole 2 of 3 · handle: its first case · type to replace · <Tab> next", echoed[#echoed])
    type_keys("<S-Tab>")
    -- the hole grew with what was typed: the whole of `id` is the hole now
    assert.equals("id", selected())
    type_keys("<Tab><Tab>")
    -- a multibyte line selects the right span
    assert.equals("todo_name", selected())
    assert.equals("hole 3 of 3 · name: a name · type to replace · <Tab> done", echoed[#echoed])
  end)

  it("<Tab> past the last hole ends it, naming the holes of other files", function()
    apply_with(stops)
    local buf
    wait(function() buf = vim.api.nvim_get_current_buf(); return holes.active(buf) end)
    flush()
    type_keys("<Tab><Tab><Tab>")
    assert.is_false(holes.active(buf))
    assert.equals("n", vim.fn.mode())
    assert.equals("spellbook: holes done · 1 more in cmd__test.py, marked (]d)", messages[#messages])
    assert.equals(0, #vim.api.nvim_buf_get_extmarks(buf, holes.ns, 0, -1, {}))
    -- our buffer-local keys are gone (a global one, like Neovim's own snippet <Tab>, may remain)
    assert.is_not.equals(1, vim.fn.maparg("<Tab>", "i", false, true).buffer)
    assert.is_not.equals(1, vim.fn.maparg("<S-Tab>", "s", false, true).buffer)
  end)

  it("a buffer-local <Tab> you had is back after the end, and no global map changed", function()
    local global = vim.fn.maparg("<Tab>", "i", false, true) -- Neovim's own (0.11+), or none
    -- a buffer-local <Tab>, as a filetype plugin would set it
    local au = vim.api.nvim_create_autocmd("BufReadPost", {
      pattern = "*cmd.py",
      callback = function(a) vim.keymap.set("i", "<Tab>", "local-tab", { buffer = a.buf, desc = "mine, local" }) end,
    })
    apply_with(stops)
    local buf
    wait(function() buf = vim.api.nvim_get_current_buf(); return holes.active(buf) end)
    vim.api.nvim_del_autocmd(au)
    flush()
    assert.equals("spellbook: next hole", vim.fn.maparg("<Tab>", "i", false, true).desc)
    holes.stop(buf)
    assert.equals("mine, local", vim.fn.maparg("<Tab>", "i", false, true).desc)
    vim.keymap.del("i", "<Tab>", { buffer = buf })
    assert.same(global, vim.fn.maparg("<Tab>", "i", false, true))
  end)

  it("names the conjure key when conjure is attached", function()
    assert.equals("hole 1 of 2 · field: x · type to replace · <Tab> next · <leader>mc conjure",
      holes.message_text(1, 2, { name = "field", instruction = "x" }, { next = "<Tab>" }, "<leader>mc"))
  end)

  it("hole_keys = false starts no session and keeps the end line", function()
    apply_with(stops, { hole_keys = false })
    wait(function() return #messages > 0 end)
    assert.is_false(holes.active(vim.api.nvim_get_current_buf()))
    assert.equals("spellbook: wrote 2 files · 1 holes, marked; ]d walks them", messages[#messages])
  end)

  it("conjure_holes = true starts no session", function()
    apply_with(stops, { conjure_holes = true })
    wait(function() return #messages > 0 end)
    assert.is_false(holes.active(vim.api.nvim_get_current_buf()))
  end)

  it("an older server (no stops) keeps today's end line", function()
    apply_with(nil)
    wait(function() return #messages > 0 end)
    assert.is_false(holes.active(vim.api.nvim_get_current_buf()))
    assert.equals("spellbook: wrote 2 files · 1 holes, marked; ]d walks them", messages[#messages])
  end)
end)

-- ---- the plan float in colour ----

describe("sorcerer.spellbook_plan", function()
  local plan_mod = require("sorcerer.spellbook_plan")
  local function extmarks(buf)
    local out = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
      table.insert(out, { row = m[2], col = m[3], hl = m[4].hl_group, end_col = m[4].end_col })
    end
    return out
  end
  local function shown(files, holes)
    local plan = { id = "x", generator = "g", files = files, holes = holes or {} }
    local buf = plan_mod.show(plan, function() end)
    return buf, vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  after_each(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(win).relative ~= "" then vim.api.nvim_win_close(win, true) end
    end
  end)

  it("a file is coloured as its language, inside its own section only", function()
    local buf, lines = shown({
      { path = "a.lua", status = "new", text = "local x = 1\n", lines = 1 },
      { path = "b.nolang", status = "new", text = "local y = 2\n", lines = 1 },
    })
    local first, second
    for i, l in ipairs(lines) do
      if l == "local x = 1" then first = i - 1 end
      if l == "local y = 2" then second = i - 1 end
    end
    local on_first, on_second = 0, 0
    for _, m in ipairs(extmarks(buf)) do
      if m.hl and m.hl:match("^@.*%.lua$") then
        if m.row == first then on_first = on_first + 1 end
        if m.row == second then on_second = on_second + 1 end
      end
    end
    assert.is_true(on_first > 0)
    assert.equals(0, on_second)
  end)

  it("a file of no known language is left plain, with no error", function()
    local buf = shown({ { path = "a.nolang", status = "new", text = "x y z\n", lines = 1 } })
    for _, m in ipairs(extmarks(buf)) do assert.is_nil(m.hl and m.hl:match("^@")) end
  end)

  it("a hole's placeholder is lit as its own span", function()
    local buf, lines = shown(
      { { path = "a.nolang", status = "new", text = "ok\n  raise X(\"hole\")\n", lines = 2 } },
      { { name = "h", kind = "block", instruction = "i", source = "placeholder", places = { { file = "a.nolang", line = 2, text = "raise X(\"hole\")" } } } }
    )
    local lit
    for _, m in ipairs(extmarks(buf)) do if m.hl == "SorcererHolePlaceholder" then lit = m end end
    assert.is_truthy(lit)
    assert.equals("  raise X(\"hole\")", lines[lit.row + 1])
    assert.equals(2, lit.col)
    assert.equals(#lines[lit.row + 1], lit.end_col)
  end)
end)

-- ---- :Spellbook check ----

describe("sorcerer.spellbook check", function()
  local fake_book = vim.fn.fnamemodify("tests/fake-spellbook", ":p")
  local root, messages, notify
  before_each(function()
    stop_all()
    vim.cmd("silent! %bwipeout!")
    root = project()
    messages, notify = {}, vim.notify
    vim.notify = function(msg) table.insert(messages, msg) end
    sorcerer.setup({ scry = { enabled = false }, spellbook = { enabled = true, cmd = { fake_book, "lsp" } } })
    vim.cmd.edit(root .. "/src/a.py")
    vim.fn.setqflist({}, "r")
  end)
  after_each(function()
    vim.notify = notify
    vim.env.FAKE_SPELLBOOK_JSON, vim.env.FAKE_SPELLBOOK_EXIT, vim.env.FAKE_SPELLBOOK_STDERR = nil, nil, nil
    vim.cmd("silent! cclose")
  end)
  local function report(findings, code)
    local path = vim.fn.tempname()
    vim.fn.writefile({ vim.json.encode({ checked = "now", findings = findings }) }, path)
    vim.env.FAKE_SPELLBOOK_JSON, vim.env.FAKE_SPELLBOOK_EXIT = path, tostring(code)
  end

  it("fills the quickfix list from the findings and opens it", function()
    report({
      { rule = "commands-use-ports", file = "src/a.py", line = 2, severity = "error", message = "talk to ports" },
      { rule = "naming", file = "src/b.py", line = 1, severity = "warn", message = "rename" },
    }, 1)
    vim.cmd("Spellbook check")
    wait(function() return #vim.fn.getqflist() == 2 end)
    local items = vim.fn.getqflist()
    assert.equals("E", items[1].type)
    assert.equals("W", items[2].type)
    assert.equals(2, items[1].lnum)
    assert.equals("commands-use-ports: talk to ports", items[1].text)
    assert.equals(vim.fs.joinpath(root, "src/a.py"), vim.api.nvim_buf_get_name(items[1].bufnr))
    assert.equals("spellbook check", vim.fn.getqflist({ title = 1 }).title)
    wait(function() return vim.fn.getqflist({ winid = 0 }).winid ~= 0 end)
  end)

  it("says the conventions hold when there is nothing", function()
    report({}, 0)
    vim.cmd("Spellbook check")
    wait(function() return #messages > 0 end)
    assert.equals("spellbook: conventions hold", messages[#messages])
    assert.equals(0, #vim.fn.getqflist())
  end)

  it("says why when the check could not run", function()
    vim.env.FAKE_SPELLBOOK_STDERR, vim.env.FAKE_SPELLBOOK_EXIT = "rules.toml: line 3", "2"
    vim.cmd("Spellbook check")
    wait(function() return #messages > 0 end)
    assert.truthy(messages[#messages]:find("rules.toml: line 3", 1, true))
  end)
end)

-- ---- :Spellbook fix ----

local FIXED = "src/a.py"
local fix_generators = {
  {
    id = "use-port", name = "Use a port the service has", summary = "Use a port",
    inputs = {
      { name = "app", type = "enum", prompt = "The app", optional = false },
      { name = "unit", type = "ident", prompt = "The unit", optional = false },
      { name = "port", type = "enum", prompt = "The port it takes", optional = false },
      { name = "note", type = "text", prompt = "A note", optional = true },
    },
  },
}
local fix_plan = {
  id = "fx12", generator = "use-port", inputs = {},
  files = {
    {
      path = FIXED, status = "changed", text = "def f(x):\n    ported\n", lines = 2, added = 1, removed = 1,
      hunks = { { header = "@@ -2,1 +2,1 @@", from = 2, to = 2, lines = { "-    pass", "+    ported" } } },
    },
    { path = "src/p.py", status = "new", text = "x = 1\n", lines = 1 },
  },
  holes = {},
  fix = { rule = "commands-use-ports", file = FIXED, line = 1, fingerprint = "ff", index = 1, label = "Use a port the service has" },
}
local fix_argument = {
  generator = "use-port", inputs = { app = "bistro", unit = "f" }, missing = { "port" },
  fix = { file = FIXED, line = 1, rule = "commands-use-ports", index = 1, label = "Use a port the service has", version = vim.NIL },
}

describe("sorcerer.spellbook :Spellbook fix", function()
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

  -- The fake's replies: the commands, the code actions of the line, and the edit the apply asks.
  local function start(extra)
    replies(vim.tbl_extend("force", {
      ["spellbook.generators"] = fix_generators,
      ["spellbook.choices_port"] = { choices = { "booking_repository", "table_repository" } },
      ["spellbook.plan"] = fix_plan,
      ["spellbook.apply"] = { changed = { FIXED }, written = { "src/p.py" }, skipped = {}, refused = vim.NIL, holes = {}, first = vim.NIL, stops = {} },
    }, extra or {}))
    local dir = vim.env.FAKE_LSP_REPLIES
    vim.fn.writefile({ vim.json.encode({
      { title = "spellbook: Use a port the service has", kind = "quickfix", isPreferred = true,
        command = { title = "x", command = "spellbook.fix", arguments = { fix_argument } } },
      { title = "spellbook: Add a port and use it", kind = "quickfix",
        command = { title = "y", command = "spellbook.fix", arguments = { fix_argument } } },
    }) }, dir .. "/textDocument_codeAction.json")
    vim.fn.writefile({ vim.json.encode({
      label = "spellbook: Use a port the service has",
      edit = { documentChanges = { {
        textDocument = { uri = vim.uri_from_fname(root .. "/" .. FIXED), version = vim.NIL },
        edits = { { range = { start = { line = 1, character = 0 }, ["end"] = { line = 1, character = 8 } }, newText = "    ported" } },
      } } },
    }) }, dir .. "/workspace_applyEdit.json")
    sorcerer.setup({ scry = { enabled = false }, spellbook = { enabled = true, cmd = { fake, "lsp" } } })
    vim.cmd.edit(root .. "/" .. FIXED)
    wait(function() return #clients() == 1 and clients()[1].initialized end)
    wait(function() return vim.tbl_contains(vim.lsp.get_clients({ bufnr = 0 }), clients()[1]) end)
  end

  local function plan_float()
    local buf
    wait(function() local w, b = float(); buf = b; return w ~= nil end)
    return buf
  end

  it("<leader>mf runs the first spellbook fix on the line, asking only what is missing", function()
    start()
    local asked = pickers({ 2 })
    vim.fn.maparg("<leader>mf", "n", false, true).callback()
    local buf = plan_float()
    assert.equals(1, #asked.select)
    assert.equals("The port it takes", asked.select[1].prompt)
    assert.equals(0, #asked.input)
    local planned = logged(log, "spellbook.plan")
    assert.equals(1, #planned)
    assert.same({ app = "bistro", unit = "f", port = "table_repository" }, planned[1][2])
    -- the finding and the buffer's version go with it; the label does not
    local fix = planned[1][3]
    assert.same({ FIXED, 1, "commands-use-ports", 1 }, { fix.file, fix.line, fix.rule, fix.index })
    assert.equals(vim.lsp.util.buf_versions[vim.api.nvim_get_current_buf()] or 0, fix.version)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("~ src/a.py (+1 −1)", lines[1])
    assert.equals("+ src/p.py (1 lines)", lines[2])
  end)

  it("the plan float shows each changed file's hunks, + lines and - lines coloured", function()
    start()
    pickers({ 1 })
    vim.fn.maparg("<leader>mf", "n", false, true).callback()
    local buf = plan_float()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local at
    for i, l in ipairs(lines) do if l == "── src/a.py ──" then at = i end end
    assert.is_truthy(at)
    assert.same({ "@@ -2,1 +2,1 @@", "-    pass", "+    ported" }, { lines[at + 1], lines[at + 2], lines[at + 3] })
    local groups = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
      if m[4].line_hl_group then groups[m[2] + 1] = m[4].line_hl_group end
    end
    assert.equals("DiffDelete", groups[at + 2])
    assert.equals("DiffAdd", groups[at + 3])
    assert.is_nil(groups[at + 1])
    -- the title names the rule, the fix and what the finding gave
    local title = vim.api.nvim_win_get_config((float())).title
    local text = type(title) == "table" and title[1][1] or title
    assert.truthy(text:find("fix commands-use-ports · Use a port the service has · 1 file changed · 1 new · app bistro, unit f (from the finding)", 1, true))
  end)

  it("<CR> applies: the server's applyEdit lands, u takes it back, the end line says what changed", function()
    start()
    pickers({ 1 })
    local buf = vim.api.nvim_get_current_buf()
    vim.fn.maparg("<leader>mf", "n", false, true).callback()
    press(plan_float(), "<CR>")
    wait(function() return #messages > 0 end)
    assert.same({ "def f(x):", "    ported", "" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    assert.is_true(vim.bo[buf].modified)
    assert.equals("spellbook: fixed commands-use-ports in a.py · changed 1 file · wrote 1 file", messages[#messages])
    -- the editor answered the server's edit, then the apply was answered
    local answered = false
    for _, line in ipairs(vim.fn.readfile(log)) do
      local msg = vim.json.decode(line)
      if msg.id == "srv-edit" and msg.method == nil then answered = msg.result.applied end
    end
    assert.is_true(answered)
    vim.api.nvim_buf_call(buf, function() vim.cmd("silent undo") end)
    assert.same({ "def f(x):", "    pass", "" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it("a fix that leaves a hole says its end line and starts the session on that hole", function()
    start({
      ["spellbook.apply"] = {
        changed = { FIXED }, written = {}, skipped = {}, refused = vim.NIL,
        holes = { { name = "port_call", kind = "block", instruction = "call the port", source = "placeholder", places = {} } },
        first = { file = FIXED, line = 2 },
        stops = { { file = FIXED, generation = "fx12", name = "port_call", kind = "block", instruction = "call the port",
          range = { start = { line = 1, character = 4 }, ["end"] = { line = 1, character = 10 } } } },
      },
    })
    pickers({ 1 })
    local buf = vim.api.nvim_get_current_buf()
    vim.fn.maparg("<leader>mf", "n", false, true).callback()
    press(plan_float(), "<CR>")
    local holes = require("sorcerer.spellbook_holes")
    wait(function() return holes.active(buf) end)
    assert.equals("spellbook: fixed commands-use-ports in a.py · changed 1 file", messages[#messages])
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    holes.stop(buf)
  end)

  it("the end line names a changed file no window shows, since it is left unsaved", function()
    start({
      ["spellbook.apply"] = { changed = { FIXED, "src/a_test.py" }, written = {}, skipped = {}, refused = vim.NIL,
        holes = {}, first = vim.NIL, stops = {} },
    })
    pickers({ 1 })
    vim.fn.maparg("<leader>mf", "n", false, true).callback()
    press(plan_float(), "<CR>")
    wait(function() return #messages > 0 end)
    assert.equals("spellbook: fixed commands-use-ports in a.py · changed 2 files · a_test.py not shown, unsaved", messages[#messages])
  end)

  it("a buffer with unsaved changes is refused, by name, and nothing is planned", function()
    start()
    vim.api.nvim_buf_set_lines(0, 0, 1, false, { "def g(x):" })
    pickers({})
    vim.fn.maparg("<leader>mf", "n", false, true).callback()
    wait(function() return #messages > 0 end)
    assert.equals("spellbook: save a.py first; a fix is planned against the file on disk", messages[1])
    vim.wait(100)
    assert.equals(0, #logged(log, "spellbook.plan"))
  end)

  it("a stop of the apply (the file changed since the plan) is said", function()
    start({ ["spellbook.apply"] = { stop = "a.py changed since the plan; nothing was applied: fix again" } })
    pickers({ 1 })
    vim.fn.maparg("<leader>mf", "n", false, true).callback()
    press(plan_float(), "<CR>")
    wait(function() return #messages > 0 end)
    assert.equals("a.py changed since the plan; nothing was applied: fix again", messages[1])
  end)

  it(":Spellbook fix port=x answers the input, so nothing is asked", function()
    start()
    local asked = pickers({})
    vim.cmd("Spellbook fix port=booking_repository")
    plan_float()
    assert.equals(0, #asked.select)
    assert.equals("booking_repository", logged(log, "spellbook.plan")[1][2].port)
  end)
end)

-- ---- owned regions: the rows, :Spellbook sync and the region's quick fix ----

local REGION_FILE = "src/b.py"
local sync_plan = {
  id = "sy12", generator = "sync", inputs = {}, holes = {}, notes = {},
  files = {
    {
      path = REGION_FILE, status = "changed", text = "x = 1\nfrom .c import C\n", lines = 2, added = 1, removed = 0, region = "exports",
      hunks = { { header = "@@ -1,1 +1,2 @@", from = 1, to = 1, lines = { " x = 1", "+from .c import C" } } },
    },
  },
}
local sync_fix_argument = {
  generator = "sync", inputs = { region = "exports", file = REGION_FILE }, missing = {},
  fix = { file = REGION_FILE, line = 1, rule = "region-stale", index = 1, label = "Sync region exports", version = vim.NIL },
}

describe("sorcerer.spellbook_plan, a region's row", function()
  it("names the region a changed file's block is, and what a set up holds", function()
    local lines = require("sorcerer.spellbook_plan").lines({
      generator = "sync", holes = {},
      files = {
        { path = "src/booking/commands/mod.rs", status = "changed", text = "", lines = 1, added = 1, region = "modules" },
        { path = "src/booking/ports/mod.rs", status = "changed", text = "", lines = 1, added = 4, region = "ports", set_up = 2 },
      },
    })
    assert.equals("~ src/booking/commands/mod.rs (region modules: +1 −0)", lines[1])
    assert.equals("~ src/booking/ports/mod.rs (region ports: set up, 2 items)", lines[2])
    assert.equals(" spellbook: sync · 2 files changed · <CR> apply · q cancel ",
      require("sorcerer.spellbook_plan").title({ generator = "sync", files = { {}, {} } }))
  end)
end)

describe("sorcerer.spellbook :Spellbook sync", function()
  local root, log, messages, notify

  before_each(function()
    stop_all()
    close_floats()
    vim.cmd("silent! %bwipeout!")
    log = vim.fn.tempname()
    vim.env.FAKE_LSP_LOG = log
    vim.env.FAKE_LSP_NAME = "spellbook"
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

  local function start(extra)
    replies(vim.tbl_extend("force", {
      ["spellbook.plan"] = sync_plan,
      ["spellbook.apply"] = { changed = { REGION_FILE }, written = {}, skipped = {}, refused = vim.NIL, holes = {}, first = vim.NIL, stops = {} },
    }, extra or {}))
    local dir = vim.env.FAKE_LSP_REPLIES
    vim.fn.writefile({ vim.json.encode({
      { title = "spellbook: Sync region exports", kind = "quickfix", isPreferred = true,
        command = { title = "Sync region exports", command = "spellbook.fix", arguments = { sync_fix_argument } } },
    }) }, dir .. "/textDocument_codeAction.json")
    vim.fn.writefile({ vim.json.encode({
      label = "spellbook: sync region exports",
      edit = { documentChanges = { {
        textDocument = { uri = vim.uri_from_fname(root .. "/" .. REGION_FILE), version = vim.NIL },
        edits = { { range = { start = { line = 1, character = 0 }, ["end"] = { line = 1, character = 0 } }, newText = "from .c import C\n" } },
      } } },
    }) }, dir .. "/workspace_applyEdit.json")
    sorcerer.setup({ scry = { enabled = false }, spellbook = { enabled = true, cmd = { fake, "lsp" } } })
    vim.cmd.edit(root .. "/" .. REGION_FILE)
    wait(function() return #clients() == 1 and clients()[1].initialized end)
    wait(function() return vim.tbl_contains(vim.lsp.get_clients({ bufnr = 0 }), clients()[1]) end)
  end

  local function plan_float()
    local buf
    wait(function() local w, b = float(); buf = b; return w ~= nil end)
    return buf
  end

  it("<leader>ms plans the sync, asking nothing, and shows the region's row and hunks", function()
    start()
    local asked = pickers({})
    vim.fn.maparg("<leader>ms", "n", false, true).callback()
    local buf = plan_float()
    assert.same({ { "sync", {} } }, vim.tbl_map(function(args) return { args[1], args[2] } end, logged(log, "spellbook.plan")))
    assert.equals(0, #logged(log, "spellbook.generators"))
    assert.equals(0, #asked.select + #asked.input)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("~ src/b.py (region exports: +1 −0)", lines[1])
    assert.truthy(vim.tbl_contains(lines, "+from .c import C"))
  end)

  it("<CR> lands the sync through the editor and says what it synced", function()
    start()
    local buf = vim.api.nvim_get_current_buf()
    vim.cmd("Spellbook sync")
    press(plan_float(), "<CR>")
    wait(function() return #messages > 0 end)
    -- an insertion past the last line: Neovim 0.10 leaves an empty line after it, 0.11 does not
    assert.same({ "x = 1", "from .c import C" }, vim.api.nvim_buf_get_lines(buf, 0, 2, false))
    assert.is_true(vim.bo[buf].modified)
    assert.equals("spellbook: synced 1 file", messages[#messages])
  end)

  it("nothing to sync is said, and no plan is shown", function()
    start({ ["spellbook.plan"] = vim.tbl_extend("force", sync_plan, { files = {} }) })
    vim.cmd("Spellbook sync")
    wait(function() return #messages > 0 end)
    assert.equals("spellbook: regions up to date", messages[1])
    assert.is_nil(float())
  end)

  it("a region file with unsaved changes is refused, by name", function()
    start()
    vim.api.nvim_buf_set_lines(0, 0, 1, false, { "x = 2" })
    vim.cmd("Spellbook sync")
    wait(function() return #messages > 0 end)
    assert.equals("spellbook: save b.py first; a fix is planned against the file on disk", messages[1])
    assert.is_nil(float())
  end)

  it("a stale region's quick fix (<leader>mf) is the sync, with its region and file", function()
    start()
    vim.fn.maparg("<leader>mf", "n", false, true).callback()
    plan_float()
    local planned = logged(log, "spellbook.plan")
    assert.equals(1, #planned)
    assert.same({ "sync", { region = "exports", file = REGION_FILE } }, { planned[1][1], planned[1][2] })
    assert.equals(0, #logged(log, "spellbook.generators"))
  end)
end)
