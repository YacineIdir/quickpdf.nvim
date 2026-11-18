-- Lifecycle of the Quickshell viewer process and the IPC calls to it.
-- Callers only need ensure(), call(), alive(), restart() and stop(); stray
-- detection and spawn polling stay in here.

local config = require("quickpdf.config")
local process = require("quickpdf.process")

local M = {}

local checked = false

local run = process.run

local function qs_config()
    return config.options.qs_config
end

-- Call a function of the `pdf` IpcHandler declared in shell.qml.
function M.call(fn, ...)
    local args = { "quickshell", "ipc", "-p", qs_config(), "call", "pdf", fn }
    for _, a in ipairs({ ... }) do
        table.insert(args, tostring(a))
    end
    return run(args)
end

function M.alive()
    return run({ "quickshell", "ipc", "-p", qs_config(), "show" }).code == 0
end

-- `quickshell ipc` refuses to pick an instance when two of the same config
-- run, so a duplicate makes every call fail and alive() report dead,
-- which would spawn a third. Kill strays before spawning, and spawn with -n.
-- pgrep -f matches any cmdline containing the pattern (a shell, this nvim),
-- so only keep pids whose comm is really the quickshell binary.
local function stray_pids()
    local res = run({ "pgrep", "-f", "quickshell -p " .. qs_config() })
    local pids = {}
    for pid in (res.stdout or ""):gmatch("%d+") do
        local f = io.open("/proc/" .. pid .. "/comm")
        if f then
            local comm = f:read("*l")
            f:close()
            if comm == "quickshell" then
                table.insert(pids, pid)
            end
        end
    end
    return pids
end

local function kill_strays()
    local pids = stray_pids()
    if #pids == 0 then
        return
    end
    run(vim.list_extend({ "kill" }, pids))
    for _ = 1, 10 do
        if #stray_pids() == 0 then
            return
        end
        vim.uv.sleep(100)
    end
    run(vim.list_extend({ "kill", "-9" }, pids))
end

-- Make sure exactly one daemon is running and answering IPC.
function M.ensure()
    if checked and M.alive() then
        return
    end
    if M.alive() then
        checked = true
        return
    end
    kill_strays()
    process.spawn({ "quickshell", "-p", qs_config(), "-d", "-n" })
    for _ = 1, 20 do
        if M.alive() then
            checked = true
            return
        end
        vim.uv.sleep(100)
    end
    vim.notify("quickpdf: Quickshell daemon did not come up", vim.log.levels.ERROR)
end

function M.restart()
    if M.alive() then
        M.call("quit")
        for _ = 1, 10 do
            if not M.alive() then
                break
            end
            vim.uv.sleep(100)
        end
    end
    checked = false
    M.ensure()
end

-- Stop the daemon and anything left over (used on VimLeavePre).
function M.stop()
    if M.alive() then
        M.call("quit")
    end
    kill_strays()
end

return M
