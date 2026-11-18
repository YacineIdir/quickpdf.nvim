-- The only place that runs external programs (hyprctl, quickshell, pdfinfo,
-- pgrep, kill). Tests replace those programs with fakes on PATH, not this
-- module (docs/adr/0004-fake-executables-instead-of-injection.md).

local M = {}

-- Run `cmd` (a list of arguments, no shell) and wait for it to finish.
-- Returns the vim.SystemCompleted table: { code, stdout, stderr }.
function M.run(cmd)
    return vim.system(cmd, { text = true }):wait()
end

-- Start `cmd` detached from Neovim and return without waiting.
function M.spawn(cmd)
    vim.system(cmd, { detach = true })
end

return M
