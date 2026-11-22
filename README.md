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
neither Rust nor a C compiler.

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
- `:checkhealth sorcerer` checks that `scry` is found.

## Status line

`require("sorcerer").status()` returns `"scry: reviewing 2 units"` while scry reviews and
`""` otherwise. For example, in lualine: `lualine_x = { require("sorcerer").status }`.
A failed review ends with `review failed, see "scry log"`, shown by your own progress display
(fidget, `vim.lsp.status()`).

## Actions

Show why, Show code and Dismiss come through your own code-action key
(`vim.lsp.buf.code_action()`, usually bound to `<leader>ca` or `gra`) on a finding's line.
The plugin binds no keys and adds no commands.

## Tests

`make test` runs the specs with plenary.nvim (found in lazy.nvim's directory, or set `DEPS`).
A Python stand-in for `scry lsp` (`tests/fake-lsp`) plays the server.

## License

Apache-2.0.
