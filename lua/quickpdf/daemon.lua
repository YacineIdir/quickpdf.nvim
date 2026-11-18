-- Lifecycle of the Quickshell viewer process and the IPC calls to it.
-- Callers only need ensure(), call(), alive(), pid(), restart() and stop();
-- stray detection and spawn polling stay in here.
--
-- Each Neovim instance runs its own daemon (ADR 0002). Quickshell tells
-- instances apart by config path, so this one reaches the configured config
-- through a symlink of its own, next to its render cache, in Neovim's temp
-- dir. Neovim deletes that dir on exit without following the link.

local config = require("quickpdf.config")
local process = require("quickpdf.process")

local M = {}

local checked = false

-- { dir, config, cache } once this instance has needed a daemon.
local instance

local run = process.run

local function ensure_instance()
    if not instance then
        local dir = vim.fn.tempname()
        local target = vim.fs.normalize(vim.fn.fnamemodify(config.options.qs_config, ":p"))
        instance = { dir = dir, config = dir .. "/" .. vim.fs.basename(target), cache = dir .. "/cache" }
        vim.fn.mkdir(instance.cache, "p")
        assert(vim.uv.fs_symlink(target, instance.config))
    end
    return instance
end

local function qs_config()
    return ensure_instance().config
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
    process.spawn({ "quickshell", "-p", qs_config(), "-d", "-n" }, { QUICKPDF_CACHE_DIR = ensure_instance().cache })
    for _ = 1, 20 do
        if M.alive() then
            checked = true
            return
        end
        vim.uv.sleep(100)
    end
    vim.notify("quickpdf: Quickshell daemon did not come up", vim.log.levels.ERROR)
end

-- Pid of this instance's daemon, or nil when none runs. Every viewer window
-- has the same title, so the pid is what tells this instance's window apart.
function M.pid()
    local res = run({ "quickshell", "list", "-p", qs_config(), "--json" })
    -- With no instance, `list` prints a sentence instead of JSON.
    local ok, list = pcall(vim.json.decode, res.stdout or "")
    if res.code == 0 and ok and type(list) == "table" and list[1] then
        return list[1].pid
    end
    return nil
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

-- Stop this instance's daemon and anything left over, then remove its config
-- link and render cache (used on VimLeavePre). An instance that never needed a
-- daemon has nothing to stop.
function M.stop()
    if not instance then
        return
    end
    if M.alive() then
        M.call("quit")
    end
    kill_strays()
    vim.fn.delete(instance.dir, "rf")
    instance = nil
    checked = false
end

return M
