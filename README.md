# sorcerer.nvim

[scry](https://github.com/sorcererdev/sorcerer) in Neovim. Save a file and scry reviews what
changed; each verified finding sits on its line, as a sign and a diagnostic. When there is
nothing to say, nothing is shown.

This plugin is thin: it starts `scry lsp` on the files you open and draws what the server
publishes. It needs Neovim 0.10 or newer and the `scry` binary:

```sh
# macOS and Linux
curl --proto '=https' --tlsv1.2 -LsSf https://github.com/sorcererdev/sorcerer/releases/latest/download/sorcerer-scry-installer.sh | sh
```

```powershell
# Windows
powershell -ExecutionPolicy ByPass -c "irm https://github.com/sorcererdev/sorcerer/releases/latest/download/sorcerer-scry-installer.ps1 | iex"
```

With Rust: `cargo install sorcerer-scry`. The installers put `scry` in `~/.local/bin` and need
neither Rust nor a C compiler. Neovim started from a terminal finds it there once your shell
has `~/.local/bin` on PATH; started from a launcher, it may need `scry = { cmd = { "/full/path/to/scry", "lsp" } }` in `setup()`.

scry reads its API keys (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `JEV_API_KEY`) from the
environment Neovim starts in. `scry doctor` in a project checks them.

## Install (lazy.nvim)

```lua
{
  "sorcererdev/sorcerer.nvim",
  opts = {},
}
```

scry is on by default, the other tools off. **Here for lackey only?** Turn scry off, or every
start says `scry` is not on the path:

```lua
{
  "sorcererdev/sorcerer.nvim",
  opts = {
    scry = { enabled = false },   -- drop this line if you installed scry too
    lackey = { enabled = true },
  },
}
```

Then see [Lackey](#lackey) below for what it needs (`claude`, a Jev key) and what to write.

## Setup

These are the defaults; pass only what you change.

```lua
require("sorcerer").setup({
  scry = {
    enabled = true,
    cmd = { "scry", "lsp" },
    -- a glyph per issue type (any other type gets •); false leaves scry's
    -- diagnostics to Neovim's own signs and virtual text
    signs = { bug = "!", assumption = "?", convention = "§", design = "~" },
    -- a bug's first sentence at the end of its line
    bug_text = true,
  },
  -- conjure (below) is off until you turn it on
  conjure = { enabled = false, cmd = { "conjure", "lsp" } },
  -- lackey (below) too
  lackey = { enabled = false, cmd = { "lackey", "lsp" } },
})
```

## What you see

- Save a file in a project (a folder with `.sorcerer/`, else a git repository) and scry
  reviews the changed units. A finding is a diagnostic on its line (source `scry`, errors for
  bugs, warnings for the rest), with a sign and a tinted line number per issue type. A bug
  also says its first sentence at the end of its line. A finding whose code changed since the
  review is dimmed.
- The first time a project's own config asks for something that runs code, scry asks whether
  to trust the project. Answer in the prompt Neovim shows.
- `:checkhealth sorcerer` checks that `scry` is found (with `scry = { enabled = false }` it says
  scry is off instead). If it is missing, Neovim says so once
  a session (not on every file) and starts no server.
- Tip: `vim.diagnostic.config({ float = { source = true } })` makes the diagnostic float show
  which tool (`scry`) said it.

## Status line

`require("sorcerer").status()` returns `"scry: reviewing 2 units"` while scry reviews and
`""` otherwise. For example, in lualine: `lualine_x = { require("sorcerer").status }`.
A failed review ends with `review failed, see "scry log"`, shown by your own progress display
(fidget, `vim.lsp.status()`).

## Work in progress

While scry reviews, conjure writes or lackey researches a question or runs a task, grey text
sits at the end of the line being worked on: `⟳ scry: reviewing…`, `⟳ conjure: writing…`,
`⟳ lackey: researching…`. Its `⟳` spins (one 90 ms timer while anything is drawn, redrawing
only buffers a window shows); `working = { animate = false }` in setup keeps it still. It is drawn from the server's
`sorcerer/working` notification (the plugin tells the server at start that it draws it), moves
with the line as you edit, and goes when the work ends or the server exits. Its highlight is
`SorcererWorking` (linked to `Comment`; set your own to change it). The status line stays.

## Keys

sorcerer binds its keys under one prefix, `<leader>m`, for the tools you turned on (lackey's
are in [its own table](#lackey)):

| key | does | needs |
|---|---|---|
| `<leader>mn` | `:Spellbook new`, a generator's files | spellbook |
| `<leader>mf` | the finding's fix on the cursor's line (the first `spellbook:` quick fix) | spellbook |
| `<leader>mc` | conjure here (normal and visual) | conjure |
| `<leader>mu` | undo the conjured change | conjure |
| `<leader>mt` | try the change again, harder | conjure |
| `<leader>mw` | show why the change was made | conjure |
| `<leader>mk` | `:Spellbook check`, the rules over the project into the quickfix list | spellbook |
| `<leader>ms` | `:Spellbook sync`, the owned regions refreshed | spellbook |

`conjure` and `undo` are the code actions **Conjure here** and **conjure: Undo** on the cursor's
line, so a line offers what it always did. Change a key, or one `false` to skip it:
`keys = { prefix = "<leader>m", undo = false, check = "x" }`; `keys = false` binds none. A key you
have already mapped is never overwritten: it is skipped and `:checkhealth sorcerer` lists it.

`:Spellbook check` runs `spellbook check --json` in the project root and fills the quickfix list
(opened when there are findings, else it says `spellbook: conventions hold`).

## Three looks

Holes, rule findings and conjured changes each have their own mark, apart from scry's and from
each other. Each is a glyph in the sign column drawn by the plugin (`false` gives Neovim's own
display back):

| mark | glyph (setting) | groups (all `default = true` links) |
|---|---|---|
| a hole | `◇` (`spellbook.signs.hole`), and the placeholder itself underlined | `SorcererHole` (`Special`), `SorcererHolePlaceholder` (`DiagnosticUnderlineHint`) |
| a rule finding | `≡` (`spellbook.signs.rule`) | `SorcererRuleError`, `SorcererRuleWarn`, `SorcererRuleHint` by severity (`DiagnosticSign*`) |
| a conjured change | `✦` (`conjure.sign`), its line number tinted | `SorcererConjured` (`DiagnosticSignOk`) |

The plan float from `:Spellbook new` also colours each new file as its language, with the
tree-sitter parser you have for it (a file whose language has no parser stays plain).

## Actions

Show why, Show code and Dismiss come through your own code-action key
(`vim.lsp.buf.code_action()`, usually `gra`) on a finding's line; scry's own actions have no
`<leader>m` key. The `<leader>m` keys above are the plugin's only maps.

## Conjure

[conjure](https://github.com/sorcererdev/sorcerer) writes one small change where you ask, in
your buffers, and marks it so you can read it, undo it or ask for a stronger attempt. It is
off by default (a scry user without it installed sees no error). Install it as you did scry
(`sorcerer-conjure-installer`, or `cargo install sorcerer-conjure`), then turn it on:

```lua
require("sorcerer").setup({ conjure = { enabled = true } })
```

It needs a project (a folder with `.sorcerer/`, else a git repository) that you have trusted
(`conjure trust` in it), and either `claude` on your PATH or an `ANTHROPIC_API_KEY` in your environment. The keys below (`<leader>mc`) run it; no code-action key is needed.

Put the cursor in a function (or select lines) and run the code action **Conjure here**; on a
line with a scry finding, **Conjure for this finding**. A progress line says `conjuring a
change`; the change appears in the buffers of every file it touched, unsaved. A **mark** (a
diagnostic, source `conjure`, on the first changed line of each file) says what it did and what
it cost, and carries the actions **conjure: Undo**, **conjure: Try harder**, **conjure: Show
why** and **conjure: Show &lt;file&gt;** for each other file. The marks clear when you save,
undo or take the next change.

The plugin starts conjure with `debounce_text_changes = 0` (Neovim reports each edit at once,
so a change never lands over what you type meanwhile) and attaches it to every buffer under
the project root, including files the change opens. `require("sorcerer").status()` joins the
two: `scry: reviewing 2 units  conjure: conjuring a change`. `:checkhealth sorcerer` checks
that `conjure` is found when it is enabled.

## Spellbook

[spellbook](https://github.com/sorcererdev/sorcerer) keeps a project's conventions as
generators: `:Spellbook new` writes every file of one (a command and its test, say) after a
preview, and leaves each **hole** (code that parses and says what belongs there) marked on its
line. It is off by default, calls no model and needs no key. Install it as you did scry
(`sorcerer-spellbook-installer`, or `cargo install sorcerer-spellbook`). Then:

```lua
require("sorcerer").setup({ spellbook = { enabled = true } })
```

`:Spellbook new [generator] [input=value…]` picks the generator and asks each input with
`vim.ui.select` and `vim.ui.input` (so your picker plugin shows them), shows the plan in a float
(`<CR>` applies, `q` cancels), writes the files, opens the first one on its first hole and marks
every hole (an Information diagnostic, source `spellbook`; `]d` walks them). The marks follow the
file on disk: save a file with a placeholder replaced and its mark goes. When conjure is on, a
hole's line already offers **Conjure here**, and the end line says `<leader>mc to conjure the
first`; with `conjure_holes = true` the plugin runs conjure on the first hole for you.

**Fixes.** A rule can name the generator that repairs its finding. On a finding's line,
`vim.lsp.buf.code_action()` lists `spellbook: Use a port the service has` first (the preferred one)
and the others after, above other servers' rewrites: the plugin orders the code-action menu with
each server's quick fixes together, its preferred one first and the servers with a preferred fix
before the others, then the rest, so another server's fix (Ruff's `Organize imports`) never sits
between spellbook's two (`fixes_first = false` keeps
Neovim's order, which follows whichever server answers first); `<leader>mf` (or `:Spellbook fix [input=value…]`) runs the first without the
menu. Save the file first (`spellbook: save close_table.py first; a fix is planned against the
file on disk`). It asks only the inputs the finding does not settle, then shows the plan in the
float: a changed file is `~ path (+3 −1)` with its hunks below, `+` lines in `DiffAdd` and `-` lines
in `DiffDelete`; a new file is `+ path` as in `new`. `<CR>` applies: the server's own
`workspace/applyEdit` lands through Neovim's handler, so `u` in each buffer takes it back (the
changed buffers are left modified; `:wa` saves them), and the new files are written. The end line
says `spellbook: fixed commands-use-ports in close_table.py · changed 2 files · wrote 4 files`; a
changed file no window shows is named (`· close_table__test.py not shown, unsaved`). If
the file changed since the plan, nothing is applied and you are told.

**Owned regions.** A project's `.sorcerer/spellbook/regions.toml` names the lists spellbook
keeps (a `mod.rs`'s `pub mod` lines, an `__init__.py`'s re-exports), each between two marker
comments. Write or delete a file such a list names and save: the block is refreshed, in its
buffer when the file is open (left modified, `u` takes it back), on disk when it is not, and the
message line says `spellbook: synced region modules in src/booking/commands/mod.rs (+1 −0)`.
With `[spellbook] sync_on_save = false` in `.sorcerer/config.toml` a stale block is a
`region-stale` error on its opening marker instead, whose quick fix (`<leader>mf`) is
`spellbook: Sync region modules`. `:Spellbook sync` (`<leader>ms`) refreshes every region: the
float shows each file as `~ path (region modules: +1 −0)` with its hunks, `<CR>` lands it as a
fix does, and nothing to do says `spellbook: regions up to date`.

**Holes work like snippet placeholders.** After the apply you land on the first hole's
placeholder, selected (select mode): type and it is replaced. `<Tab>` moves to the next hole,
`<S-Tab>` back; the message line says where you are, `hole 1 of 3 · field: its first input · type
to replace · <Tab> next · <leader>mc conjure` (the conjure part when conjure is on). A hole grows
with what you type, so `<S-Tab>` selects your whole answer again. `<Tab>` on the last hole ends
it (`spellbook: holes done`), and so does closing the buffer. The session walks the holes of the
file it opened; a hole in another file (the test, say) stays marked, and the end line names it:
`spellbook: holes done · 1 more in command__test.py, marked (]d)`. The placeholders stay code
that parses while you walk them. The keys are that buffer's own, in insert and select mode only:
normal-mode `<Tab>` and your global maps (a completion plugin's `<Tab>`) are never touched, and a
buffer-local map you had on those keys is put back at the end. No session runs with
`conjure_holes = true` (conjure fills the first hole) or `hole_keys = false`.

| setting | default | |
|---|---|---|
| `spellbook.enabled` | `false` | start `spellbook lsp` for the files you open |
| `spellbook.cmd` | `{ "spellbook", "lsp" }` | the program, if not on your PATH |
| `spellbook.conjure_holes` | `false` | conjure the first hole after `:Spellbook new` |
| `spellbook.hole_keys` | `{ next = "<Tab>", prev = "<S-Tab>" }` | the keys between holes after `:Spellbook new`; `false` = no session |
| `fixes_first` | `true` | the code-action menu lists each server's quick fixes together (preferred first, servers with a preferred fix first), then the rest; `false` = Neovim's order |

The project must be trusted (`spellbook trust`) when its own config runs code.
`:checkhealth sorcerer` checks that `spellbook` is found when it is enabled.

## Lackey

[lackey](https://github.com/sorcererdev/sorcerer) is a coding agent whose whole interface is
your editor: no chat. The whole first-time path is
[Getting started](https://github.com/sorcererdev/sorcerer/blob/main/book/user/src/lackey.md#getting-started)
in the user book; in short:

1. Install it as you would scry (`sorcerer-lackey-installer.sh` / `.ps1` from the
   [release](https://github.com/sorcererdev/sorcerer/releases/latest), or
   `cargo install sorcerer-lackey`).
2. It runs Claude Code (`claude -p`) on your own subscription: install
   [Claude Code](https://docs.anthropic.com/en/docs/claude-code), run `claude` once in a
   terminal and log in.
3. Jev reads what you write: sign up at [typesafe.ai](https://typesafe.ai) (free) and
   `export JEV_API_KEY=…` in your shell profile, then restart Neovim from a new terminal.
   Without it only empty function bodies are offered.
4. `lackey doctor` in a project: every row `ok` (`warn` says what lackey will not do).
5. Turn it on (scry off unless you installed it):

```lua
require("sorcerer").setup({
  scry = { enabled = false },   -- drop this line if you installed scry too
  lackey = { enabled = true },
})
```

**Your first offer.** In a Python file of a git repository (or any code language sorcerer ships,
in its own comment), on a line of its own at the end (not inside a function), write `# Add a
median(prices) function that returns the middle price.` and stop typing. About two seconds later a faint `lackey: I can do this · ~$0.50 ·
sonnet` hint appears; `<leader>ma` runs it. A comment inside a function that describes a change
may be read as an aside and get no offer: `<leader>ma` then says `lackey: no offer on this
line`; put the request above the function, start it with what to do, or label the line
(`<leader>ml`).

Write in your code: a comment, a sentence in a docstring, an empty body. On idle lackey asks
Jev what it is; on save it answers a question or checks a claim, in the margin (source
`lackey`), and an instruction is offered as the code action `lackey: do this · ~$0.50 ·
sonnet`. Accepting runs a task: its changes land in your buffers (unsaved, `u` undoes them), the
status line says what it does, a question it asks is choices on a line or a list, and at the end
a `✦ lackey: …` mark on each changed file offers **Show diff** (the file before the task
against now, side by side in diff mode in a tab of its own; `:tabclose` ends it), **Undo this task** and **Show journal**. Saving every
file it changed keeps the task.

The plugin starts `lackey lsp` with `debounce_text_changes = 0` and on every buffer under the
root, as for conjure, and draws what the server sends only to it: grey suggested lines under a
line (`SorcererGhost`, linked to `Comment`; gone at your next edit of the line), the agent's
notes in a vertical split beside your code, and the diff view. Its keys:

| key | does |
|---|---|
| `<leader>ma` | **lackey: do this** on the line (whatever its price); with no offer there, it says so |
| `<leader>mo` | **lackey: Open the answer**: a long answer, beside your code (none opens unasked) |
| `<leader>mq` | **lackey: Stop this task** (q for quit; `s` is spellbook sync) |
| `<leader>md` | **lackey: Show diff** |
| `<leader>mz` | **lackey: Undo this task** |
| `<leader>mj` | **lackey: Show journal** |
| `<leader>mx` | **lackey: Dismiss** a mark |
| `<leader>ml` | label the line: what it really was (a question, a claim, an instruction, nothing) |

`require("sorcerer").status()` says `lackey: <task> · <what it does> · $0.12` while a task
runs.

## Tests

`make test` runs the specs with plenary.nvim (found in lazy.nvim's directory, or set `DEPS`).
A Python stand-in for `scry lsp` (`tests/fake-lsp`) plays any of the servers.

## License

Apache-2.0.
