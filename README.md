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
- `:checkhealth sorcerer` checks that `scry` is found. If it is missing, Neovim says so once
  a session (not on every file) and starts no server.
- Tip: `vim.diagnostic.config({ float = { source = true } })` makes the diagnostic float show
  which tool (`scry`) said it.

## Status line

`require("sorcerer").status()` returns `"scry: reviewing 2 units"` while scry reviews and
`""` otherwise. For example, in lualine: `lualine_x = { require("sorcerer").status }`.
A failed review ends with `review failed, see "scry log"`, shown by your own progress display
(fidget, `vim.lsp.status()`).

## Work in progress

While scry reviews or conjure writes, grey text sits at the end of the first line of each unit
being worked on: `⟳ scry: reviewing…`, `⟳ conjure: writing…`. It is drawn from the server's
`sorcerer/working` notification (the plugin tells the server at start that it draws it), moves
with the line as you edit, and goes when the work ends or the server exits. Its highlight is
`SorcererWorking` (linked to `Comment`; set your own to change it). The status line stays.

## Actions

Show why, Show code and Dismiss come through your own code-action key
(`vim.lsp.buf.code_action()`, usually bound to `<leader>ca` or `gra`) on a finding's line.
The plugin binds no keys and adds no commands.

## Conjure

[conjure](https://github.com/sorcererdev/sorcerer) writes one small change where you ask, in
your buffers, and marks it so you can read it, undo it or ask for a stronger attempt. It is
off by default (a scry user without it installed sees no error). Install it as you did scry
(`sorcerer-conjure-installer`, or `cargo install sorcerer-conjure`), then turn it on:

```lua
require("sorcerer").setup({ conjure = { enabled = true } })
```

It needs a project (a folder with `.sorcerer/`, else a git repository) that you have trusted
(`conjure trust` in it), and `claude` on your PATH. Bind the code-action key if you have not:

```lua
vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action)
```

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

## Tests

`make test` runs the specs with plenary.nvim (found in lazy.nvim's directory, or set `DEPS`).
A Python stand-in for `scry lsp` (`tests/fake-lsp`) plays either server.

## License

Apache-2.0.
