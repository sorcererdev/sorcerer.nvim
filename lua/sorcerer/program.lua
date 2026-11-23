-- Whether a language server's program can run, asked once a Neovim session per program.
-- A missing program is reported once (one warning naming it, the setting and the install
-- line) and its server is not started again for each buffer that opens.
local M = {}

-- the README's install line for each program on this platform
local windows = vim.fn.has("win32") == 1
M.install = {
  scry = windows
      and [[powershell -ExecutionPolicy ByPass -c "irm https://github.com/sorcererdev/sorcerer/releases/latest/download/sorcerer-scry-installer.ps1 | iex"]]
    or [[curl --proto '=https' --tlsv1.2 -LsSf https://github.com/sorcererdev/sorcerer/releases/latest/download/sorcerer-scry-installer.sh | sh]],
  conjure = windows
      and [[powershell -ExecutionPolicy ByPass -c "irm https://github.com/sorcererdev/sorcerer/releases/latest/download/sorcerer-conjure-installer.ps1 | iex"]]
    or [[curl --proto '=https' --tlsv1.2 -LsSf https://github.com/sorcererdev/sorcerer/releases/latest/download/sorcerer-conjure-installer.sh | sh]],
}

-- program -> true when it was found, false when it was missing (and said so)
local checked = {}

-- Forget what was checked, so the next attach asks again (setup calls this).
function M.forget()
  checked = {}
end

-- True when the program NAME ("scry" or "conjure") can run as CMD's first word. The first
-- time it cannot, warn once; every later call answers from the first.
function M.runnable(name, cmd)
  if checked[name] ~= nil then return checked[name] end
  local exe = cmd[1]
  checked[name] = vim.fn.executable(exe) == 1
  if not checked[name] then
    vim.notify(
      ("sorcerer: `%s` is not on the path, so %s's language server is not started. "
        .. "Set %s.cmd in setup() to its full path, or install it: %s"):format(exe, name, name, M.install[name]),
      vim.log.levels.WARN
    )
  end
  return checked[name]
end

return M
