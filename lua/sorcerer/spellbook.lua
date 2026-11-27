-- spellbook's language server: `spellbook lsp`, the sorcerer suite's generators and rules. The
-- server shows each open hole of a generated file as a mark (a diagnostic) on save and open, and
-- runs the four commands `:Spellbook new` asks with Neovim's own pickers.
-- spellbook is attached to every buffer under the project root, so it sees each file opened or
-- saved; one client a project root (Neovim reuses a client with the same name and root). The
-- root is the nearest `.sorcerer/` upward, else the nearest `.git`, the server's own order.
local M = {}

local opts = nil

-- the generator name of a sync of the owned regions (`:Spellbook sync`, a region's quick fix)
local SYNC = "sync"
-- defined below, with `:Spellbook sync`
local planned_sync

-- The project root of buffer BUF, or nil.
function M.root(buf)
  return vim.fs.root(buf, ".sorcerer") or vim.fs.root(buf, ".git")
end

-- Attach spellbook to buffer BUF when it is enabled and BUF is a file under a project root.
function M.attach(buf)
  if not opts or not opts.enabled then return end
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then return end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or not vim.uv.fs_stat(name) then return end
  local root = M.root(buf)
  if not root then return end
  if not require("sorcerer.program").runnable("spellbook", opts.cmd) then return end
  vim.lsp.start({
    name = "spellbook",
    cmd = opts.cmd,
    root_dir = root,
    -- the command of the server's quick fixes: the editor runs it, not the server
    commands = { ["spellbook.fix"] = function(cmd, ctx) M.fix(cmd.arguments and cmd.arguments[1], ctx) end },
  }, { bufnr = buf })
end

-- A file written for the first time (a new file, which has no client until it is on disk) is
-- attached only after its write, so Neovim sends no `didSave` for it: send it, so the server's
-- save work (a hole's mark, a region synced on save) runs on this save and not the next one. A
-- client still starting is waited for, a few seconds at most.
-- Example: `:e commands/close_table.rs`, type, `:w` syncs `commands/mod.rs` at once.
function M.first_save(buf, tries)
  local client = vim.lsp.get_clients({ name = "spellbook", bufnr = buf })[1]
  if not client or not vim.api.nvim_buf_is_valid(buf) then return end
  if not client.initialized then
    if (tries or 0) < 50 then vim.defer_fn(function() M.first_save(buf, (tries or 0) + 1) end, 100) end
    return
  end
  local params = { textDocument = { uri = vim.uri_from_bufnr(buf) } }
  if vim.fn.has("nvim-0.11") == 1 then client:notify("textDocument/didSave", params) else client.notify("textDocument/didSave", params) end
end

-- spellbook shows no progress line, so it has nothing for the status line.
function M.status()
  return ""
end

-- ---- :Spellbook new ----
-- The one place a client here holds more than the three replies' shapes: it asks the server for
-- the generators, the choices of an input and the plan, with the editor's own pickers, then
-- applies. The replies are `{ stop = <sentence> }` (with `input` and `choices` for a missing
-- input) or: generators `[{ id, name, summary, inputs = [{ name, type, prompt, optional }] }]`,
-- choices `{ choices }`, a plan `{ id, generator, files = [{ path, status, text, lines }],
-- holes = [{ name, kind, instruction, source, places = [{ file, line }] }] }`, and an apply
-- `{ written, skipped, refused, holes, first = { file, line }, stops = [{ file, name, kind,
-- instruction, range }] }` (`stops`: each hole's placeholder, UTF-16 range; absent from an older server).

-- how long to wait for the server's own `window/showDocument` to open the first hole
M.show_wait_ms = 2000

-- Ask CLIENT for METHOD; HANDLER(err, result, ctx). Neovim 0.11 made `request` a method.
local function request(client, method, params, handler)
  if vim.fn.has("nvim-0.11") == 1 then
    client:request(method, params, handler)
  else
    client.request(method, params, handler)
  end
end

-- VALUE with every JSON null (`vim.NIL`, which is truthy) taken out, so a reply's `first = null`
-- is nil to the code that reads it.
local function without_nulls(value)
  if value == vim.NIL then return nil end
  if type(value) ~= "table" then return value end
  local clean = {}
  for key, item in pairs(value) do clean[key] = without_nulls(item) end
  return clean
end

-- Run the server COMMAND with ARGUMENTS; HANDLER(reply). A failed request says so.
local function command(client, name, arguments, handler)
  request(client, "workspace/executeCommand", { command = name, arguments = arguments }, function(err, reply)
    if err or reply == nil then
      vim.notify(("spellbook: %s failed: %s"):format(name, err and err.message or "no reply"), vim.log.levels.ERROR)
      return
    end
    handler(without_nulls(reply))
  end)
end

local function say(text, level)
  vim.notify(text, level or vim.log.levels.INFO)
end

-- The spellbook client of the current buffer's project, or nil.
local function client_here()
  local buf = vim.api.nvim_get_current_buf()
  local here = vim.lsp.get_clients({ name = "spellbook", bufnr = buf })[1]
  if here then return here end
  local root = M.root(buf)
  for _, client in ipairs(vim.lsp.get_clients({ name = "spellbook" })) do
    if client.config.root_dir == root then return client end
  end
end

-- Ask the value of INPUT (the generator's input table); DONE(value) with nil for a cancel.
-- CHOICES are the values of an enum, already known.
local function ask_value(input, choices, done)
  if choices then
    local items = vim.list_extend(input.optional and { "(skip)" } or {}, choices)
    vim.ui.select(items, { prompt = input.prompt }, function(item)
      if item == "(skip)" then item = "" end
      done(item)
    end)
  else
    local prompt = input.prompt .. (input.optional and " (empty to skip)" or "") .. ": "
    vim.ui.input({ prompt = prompt }, function(text)
      if text ~= nil then text = vim.trim(text) end
      done(text)
    end)
  end
end

-- Resolve each of GENERATOR's inputs in order, the given ones kept; DONE(inputs). With ONLY (a
-- list of names), the inputs it does not name are left alone: a fix asks what its finding does
-- not settle.
local function ask_inputs(client, generator, given, done, only)
  local values = vim.deepcopy(given)
  local function step(i)
    local input = generator.inputs[i]
    if not input then return done(values) end
    local function take(value)
      if value == nil then return end -- cancelled
      if value ~= "" then values[input.name] = value end
      step(i + 1)
    end
    if values[input.name] then return step(i + 1) end
    if only and not vim.tbl_contains(only, input.name) then return step(i + 1) end
    if input.type ~= "enum" then return ask_value(input, nil, take) end
    command(client, "spellbook.choices", { generator.id, values, input.name }, function(reply)
      if reply.stop then return say(reply.stop, vim.log.levels.WARN) end
      if #reply.choices == 1 and not input.optional then return take(reply.choices[1]) end
      ask_value(input, reply.choices, take)
    end)
  end
  step(1)
end

-- The plan for GENERATOR and VALUES (and the finding FIX answers, when there is one); a stop that
-- names an input asks that input once more.
local function make_plan(client, generator, values, retried, done, fix)
  command(client, "spellbook.plan", fix and { generator.id, values, fix } or { generator.id, values }, function(reply)
    if not reply.stop then return done(reply) end
    if reply.input and not retried then
      local input = vim.tbl_filter(function(i) return i.name == reply.input end, generator.inputs)[1]
      if input then
        say(reply.stop, vim.log.levels.WARN)
        return ask_value(input, #(reply.choices or {}) > 0 and reply.choices or nil, function(value)
          if value == nil or value == "" then return end
          values[input.name] = value
          make_plan(client, generator, values, true, done, fix)
        end)
      end
    end
    say(reply.stop, vim.log.levels.WARN)
  end)
end

-- The conjure client of the project CLIENT serves, or nil.
local function conjure_for(client)
  for _, c in ipairs(vim.lsp.get_clients({ name = "conjure" })) do
    if c.config.root_dir == client.config.root_dir then return c end
  end
end

local function holes_to_fill(holes)
  local n = 0
  for _, hole in ipairs(holes or {}) do
    if hole.source == "placeholder" then n = n + 1 end
  end
  return n
end

-- The hole session keys, or nil when there is to be no session: `hole_keys = false`, or
-- conjure filling the first hole itself (`conjure_holes`).
local function session_keys()
  if not opts or opts.hole_keys == false or opts.conjure_holes then return nil end
  return vim.tbl_extend("force", { next = "<Tab>", prev = "<S-Tab>" }, opts.hole_keys or {})
end

-- Start the hole session on the first hole's file ABS (shown by now) over REPLY's stops in that
-- file; the holes of other files are counted for the end line. The stops are the holes this
-- apply wrote (the server leaves out older ones). False when there is none to run: no stops (an
-- older server), no hole to fill in the plan, no keys, or the file is not in a window.
local function start_holes(reply, abs, conjure)
  local keys = session_keys()
  local stops = reply.stops or {}
  if not keys or #stops == 0 or holes_to_fill(reply.holes) == 0 then return false end
  local mine, others = {}, {}
  for _, stop in ipairs(stops) do
    if stop.file == stops[1].file then
      table.insert(mine, stop)
    else
      local name = vim.fs.basename(stop.file)
      others[name] = (others[name] or 0) + 1
    end
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" and vim.fs.normalize(name) == abs then
      vim.api.nvim_set_current_win(win)
      local conjure_lhs = conjure and require("sorcerer.keys").lhs("conjure") or nil
      require("sorcerer.spellbook_holes").start(buf, mine, keys, conjure_lhs, others)
      return true
    end
  end
  return false
end

-- The changed files (paths from ROOT) that no window shows: the fix's edit left them unsaved in
-- hidden buffers, so the end line names them.
local function not_shown(root, changed)
  local shown = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
    if name ~= "" then shown[vim.fs.normalize(name)] = true end
  end
  return vim.tbl_filter(function(path)
    return not shown[vim.fs.normalize(vim.fs.joinpath(root, path))]
  end, changed or {})
end

-- After an apply: the end line, always, and the first hole's file open, its holes as a session
-- of snippet placeholders (spellbook_holes.lua; the session's hole message follows the end line)
-- or else the holes counted on the end line, and conjure on the first hole when asked. The
-- server asks the editor to show the file; when it has not within the wait, do it.
-- FIXED ({ rule, file }) is set after a fix: the end line then says what it changed.
local function finish(client, reply, fixed)
  local first = reply.first
  local conjure = conjure_for(client)
  local function end_text()
    return M.end_text(reply, fixed, fixed and not fixed.sync and not_shown(client.config.root_dir, reply.changed) or {})
  end
  local function end_line()
    local n = holes_to_fill(reply.holes)
    local text = end_text()
    if n > 0 then
      local key = require("sorcerer.keys").lhs("conjure")
      text = text .. (conjure and (" · %d holes · %s to conjure the first"):format(n, key or "Conjure here (a code action)")
        or (" · %d holes, marked; ]d walks them"):format(n))
    end
    say(text)
    if first and conjure and opts and opts.conjure_holes then
      local abs = vim.fs.joinpath(client.config.root_dir, first.file)
      request(conjure, "workspace/executeCommand", {
        command = "conjure.conjure",
        arguments = { vim.uri_from_fname(abs), first.line },
      }, function() end)
    end
  end
  if not first then return end_line() end
  local abs = vim.fs.normalize(vim.fs.joinpath(client.config.root_dir, first.file))
  local waited, timer = 0, assert(vim.uv.new_timer())
  timer:start(0, 50, vim.schedule_wrap(function()
    local shown = false
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
      if name ~= "" and vim.fs.normalize(name) == abs then shown = true end
    end
    waited = waited + 50
    if not shown and waited <= M.show_wait_ms then return end
    timer:stop()
    timer:close()
    if not shown then
      if pcall(vim.cmd.edit, vim.fn.fnameescape(abs)) then
        pcall(vim.api.nvim_win_set_cursor, 0, { first.line, 0 })
      else
        say(("spellbook: could not open %s; the first hole is at line %d"):format(abs, first.line), vim.log.levels.WARN)
        return end_line()
      end
    end
    if start_holes(reply, abs, conjure) then
      say(end_text())
    else
      end_line()
    end
  end))
end

-- The first part of the end line: what was written, or after a fix (FIXED = { rule, file }) what
-- it fixed, changed (naming at most three changed files in HIDDEN, which no window shows) and
-- wrote; a sync (FIXED.sync) what it synced.
-- Example: `spellbook: wrote 2 files`; `spellbook: synced 1 file`;
-- `spellbook: fixed commands-use-ports in close_table.py · changed 2 files · close_table__test.py
-- not shown, unsaved · wrote 4 files`.
function M.end_text(reply, fixed, hidden)
  local function files(n) return ("%d %s"):format(n, n == 1 and "file" or "files") end
  if fixed and fixed.sync then return ("spellbook: synced %s"):format(files(#(reply.changed or {}))) end
  if not fixed then return ("spellbook: wrote %s"):format(files(#reply.written)) end
  local text = ("spellbook: fixed %s in %s · changed %s"):format(fixed.rule, vim.fs.basename(fixed.file), files(#(reply.changed or {})))
  hidden = hidden or {}
  if #hidden > 0 then
    local names = vim.tbl_map(vim.fs.basename, vim.list_slice(hidden, 1, 3))
    local more = #hidden > 3 and (" and %d more"):format(#hidden - 3) or ""
    text = text .. (" · %s%s not shown, unsaved"):format(table.concat(names, ", "), more)
  end
  if #reply.written > 0 then text = text .. " · wrote " .. files(#reply.written) end
  return text
end

-- Apply PLAN. A plan with changed files makes the server send `workspace/applyEdit` before it
-- answers; Neovim's own handler for it lands the edit (one undo step per buffer, the buffers left
-- modified), so nothing here waits on it or replaces it. FIXED: see finish.
local function apply(client, plan, fixed)
  command(client, "spellbook.apply", { plan.id }, function(reply)
    if reply.stop then return say(reply.stop, vim.log.levels.WARN) end
    if reply.refused and reply.refused ~= vim.NIL then
      say(("spellbook: %s was not written: %s"):format(reply.refused.path, reply.refused.why), vim.log.levels.WARN)
    end
    finish(client, reply, fixed)
  end)
end

-- `:Spellbook new [generator] [input=value…]`: pick, answer, preview the plan, apply.
function M.new(args)
  local client = client_here()
  if not client then
    return say("spellbook: open a file in the project first (and check `spellbook.enabled` and that the spellbook binary is installed)", vim.log.levels.WARN)
  end
  local named, given = nil, {}
  for _, arg in ipairs(args) do
    local name, value = arg:match("^([%w_%-]+)=(.*)$")
    if name then given[name] = value else named = arg end
  end
  command(client, "spellbook.generators", {}, function(generators)
    local function with(generator)
      ask_inputs(client, generator, given, function(values)
        make_plan(client, generator, values, false, function(plan)
          require("sorcerer.spellbook_plan").show(plan, function() apply(client, plan) end)
        end)
      end)
    end
    if named then
      local generator = vim.tbl_filter(function(g) return g.id == named end, generators)[1]
      if not generator then return say(("spellbook: no generator named %s"):format(named), vim.log.levels.WARN) end
      return with(generator)
    end
    if #generators == 0 then return say("spellbook: this project has no generators", vim.log.levels.WARN) end
    vim.ui.select(generators, {
      prompt = "Generator",
      format_item = function(g) return g.name .. " — " .. g.summary end,
    }, function(generator)
      if generator then with(generator) end
    end)
  end)
end

-- ---- :Spellbook fix ----

-- the `input=value` words of a `:Spellbook fix` line, taken by the next fix that runs
local extra_inputs = {}

-- The sentence for a buffer with unsaved changes.
-- Example: `spellbook: save close_table.py first; a fix is planned against the file on disk`.
function M.dirty_text(file)
  return ("spellbook: save %s first; a fix is planned against the file on disk"):format(vim.fs.basename(file))
end

-- Run the fix a quick fix carries: ARG is the code action's command argument `{ generator,
-- inputs, missing, fix }` and CTX the buffer it was asked in. The buffer must be saved (the plan
-- is made on the file on disk); then it is the New chain from step 2: the generator is the
-- fix's, the inputs the finding settled are kept, only `missing` is asked, and the plan gets the
-- finding with the buffer's version. Applying lands the changed files through `applyEdit`.
function M.fix(arg, ctx)
  local given = extra_inputs
  extra_inputs = {}
  local fix = type(arg) == "table" and arg.fix
  if not fix or not arg.generator then
    return say("spellbook: this fix has no shape this plugin knows; update sorcerer.nvim", vim.log.levels.WARN)
  end
  local buf = ctx and ctx.bufnr or vim.api.nvim_get_current_buf()
  if vim.bo[buf].modified then return say(M.dirty_text(fix.file), vim.log.levels.WARN) end
  local client = (ctx and ctx.client_id and vim.lsp.get_client_by_id(ctx.client_id)) or client_here()
  if not client then
    return say("spellbook: open a file in the project first", vim.log.levels.WARN)
  end
  if arg.generator == SYNC then return planned_sync(client, arg.inputs or {}) end
  local request_fix = {
    file = fix.file, line = fix.line, rule = fix.rule, index = fix.index,
    version = vim.lsp.util.buf_versions[buf] or 0,
  }
  command(client, "spellbook.generators", {}, function(generators)
    local generator = vim.tbl_filter(function(g) return g.id == arg.generator end, generators)[1]
    if not generator then return say(("spellbook: no generator named %s"):format(arg.generator), vim.log.levels.WARN) end
    local inputs = vim.tbl_extend("force", arg.inputs or {}, given)
    ask_inputs(client, generator, inputs, function(values)
      make_plan(client, generator, values, false, function(plan)
        require("sorcerer.spellbook_plan").show(plan, function() apply(client, plan, { rule = fix.rule, file = fix.file }) end, arg.inputs)
      end, request_fix)
    end, arg.missing)
  end)
end

-- ---- :Spellbook sync ----

-- The plan of a sync, shown, then applied: the New chain entered at the plan with the generator
-- `sync`, which the server knows by name (nothing is asked). Nothing to do is said instead, with
-- the plan's notes (a region not set up). INPUTS: a region's quick fix gives its region and file.
-- A changed region file with unsaved changes in a buffer is refused, by name: the edit is made
-- against the file on disk.
planned_sync = function(client, inputs)
  command(client, "spellbook.plan", { SYNC, inputs }, function(plan)
    if plan.stop then return say(plan.stop, vim.log.levels.WARN) end
    if #(plan.files or {}) == 0 then
      return say(table.concat(vim.list_extend({ "spellbook: regions up to date" }, plan.notes or {}), " · "))
    end
    for _, file in ipairs(plan.files) do
      local buf = vim.fn.bufnr(vim.fs.joinpath(client.config.root_dir, file.path))
      if buf ~= -1 and vim.bo[buf].modified then return say(M.dirty_text(file.path), vim.log.levels.WARN) end
    end
    require("sorcerer.spellbook_plan").show(plan, function() apply(client, plan, { sync = true }) end)
  end)
end

-- `:Spellbook sync`: every owned region refreshed, the plan shown (each region file's hunks),
-- <CR> lands it through the editor.
function M.sync()
  local client = client_here()
  if not client then
    return say("spellbook: open a file in the project first (and check `spellbook.enabled` and that the spellbook binary is installed)", vim.log.levels.WARN)
  end
  planned_sync(client, {})
end

-- True for the quick fix that runs `spellbook.fix`.
function M.is_fix(action)
  return type(action.command) == "table" and action.command.command == "spellbook.fix"
end

-- Run the first spellbook fix offered on the cursor's line; GIVEN (`input=value` words) answers
-- inputs the finding does not settle.
function M.fix_here(given)
  extra_inputs = given or {}
  local taken = false
  vim.lsp.buf.code_action({
    apply = true,
    context = { only = { "quickfix" } },
    filter = function(action)
      if taken or not M.is_fix(action) then return false end
      taken = true
      return true
    end,
  })
  -- Neovim says `No code actions available` when the line has none; the words wait no longer
  vim.defer_fn(function()
    if not taken then extra_inputs = {} end
  end, 1000)
end

-- ---- :Spellbook check ----

-- The quickfix items of `spellbook check --json`'s FINDINGS, their files under ROOT.
-- Example: { rule = "commands-use-ports", file = "src/a.py", line = 2, severity = "error" }
-- becomes an `E` item at src/a.py:2.
local function check_items(findings, root)
  local types = { error = "E", warn = "W", hint = "I" }
  local items = {}
  for _, f in ipairs(findings) do
    table.insert(items, {
      filename = vim.fs.joinpath(root, f.file),
      lnum = f.line,
      type = types[f.severity] or "I",
      text = ("%s: %s"):format(f.rule, f.message),
    })
  end
  return items
end

-- `:Spellbook check`: run the rules over the project and list the findings in the quickfix
-- list (opened when there are any), else say the conventions hold.
function M.check()
  local root = M.root(0) or vim.uv.cwd()
  local cmd = { opts and opts.cmd and opts.cmd[1] or "spellbook", "check", "--json" }
  vim.system(cmd, { cwd = root, text = true }, vim.schedule_wrap(function(done)
    if done.code ~= 0 and done.code ~= 1 then
      local why = vim.trim((done.stderr or "") ~= "" and done.stderr or (done.stdout or ""))
      return say(("spellbook: check could not run: %s"):format(why), vim.log.levels.ERROR)
    end
    local ok, report = pcall(vim.json.decode, done.stdout or "")
    if not ok or type(report) ~= "table" then
      return say("spellbook: check printed something unreadable", vim.log.levels.ERROR)
    end
    local items = check_items(report.findings or {}, root)
    vim.fn.setqflist({}, " ", { title = "spellbook check", items = items })
    if #items == 0 then return say("spellbook: conventions hold") end
    vim.cmd("copen")
  end))
end

-- OPTS is the `spellbook` table of setup.
function M.setup(o)
  opts = o
  vim.api.nvim_create_user_command("Spellbook", function(c)
    local sub = table.remove(c.fargs, 1)
    if sub == "new" then return M.new(c.fargs) end
    if sub == "check" then return M.check() end
    if sub == "sync" then return M.sync() end
    if sub == "fix" then
      local given = {}
      for _, arg in ipairs(c.fargs) do
        local name, value = arg:match("^([%w_%-]+)=(.*)$")
        if name then given[name] = value end
      end
      return M.fix_here(given)
    end
    say("spellbook: use `:Spellbook new [generator] [input=value…]`, `:Spellbook fix [input=value…]`, `:Spellbook sync` or `:Spellbook check`", vim.log.levels.WARN)
  end, {
    nargs = "*",
    complete = function(lead, line)
      if not line:match("^%s*Spellbook%s+%S*$") then return {} end
      return vim.tbl_filter(function(s) return vim.startswith(s, lead) end, { "new", "fix", "sync", "check" })
    end,
    desc = "spellbook: write a generator's files",
  })
  require("sorcerer.program").forget()
  local group = vim.api.nvim_create_augroup("sorcerer_spellbook", { clear = true })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufWritePost", "BufEnter" }, {
    group = group,
    callback = function(a)
      local was_attached = #vim.lsp.get_clients({ name = "spellbook", bufnr = a.buf }) > 0
      M.attach(a.buf)
      if a.event == "BufWritePost" and not was_attached then M.first_save(a.buf) end
    end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then M.attach(buf) end
  end
end

return M
