-- Spike #14: which ways of learning the terminal cell size in pixels work
-- from inside Neovim. Run it in the terminal under test, with a Hyprland
-- session around it:
--
--   QUICKPDF_PROBE_OUT=/tmp/kitty.json kitty nvim --clean -c "luafile docs/spikes/pixel-geometry-probe.lua"
--
-- It writes one JSON object to $QUICKPDF_PROBE_OUT and quits:
--   grid        columns and lines Neovim sees
--   termresponse  sequences TermResponse received after CSI 16 t and CSI 14 t
--   keys        raw input received meanwhile (a reply Neovim does not parse
--               may arrive as keys)
--   winsize     TIOCGWINSZ of the terminal, through the TUI process's pty
--   window      the terminal's Hyprland window (size, at), found by pid

local ffi = require("ffi")

local out = assert(os.getenv("QUICKPDF_PROBE_OUT"), "set QUICKPDF_PROBE_OUT")
local result = { term = os.getenv("TERM"), termresponse = {}, keys = {} }

ffi.cdef([[
    struct qpdf_winsize { unsigned short row, col, xpixel, ypixel; };
    int open(const char *path, int flags);
    int close(int fd);
    int ioctl(int fd, unsigned long request, ...);
]])
local O_RDONLY, O_NOCTTY, TIOCGWINSZ = 0, 256, 0x5413

local function parent(pid)
    local f = io.open("/proc/" .. pid .. "/stat")
    if not f then
        return nil
    end
    local stat = f:read("*l")
    f:close()
    -- The command name may contain spaces; the ppid is the 2nd field after ")".
    return tonumber(stat:match("%) %S+ (%d+)"))
end

-- The server has no terminal since Neovim 0.10: the TUI is its parent
-- process, and its stdin is the pty.
local function winsize()
    local tui = parent(vim.fn.getpid())
    local pty = tui and vim.uv.fs_readlink("/proc/" .. tui .. "/fd/0")
    if not pty then
        return { error = "no TUI pty" }
    end
    local fd = ffi.C.open(pty, O_RDONLY + O_NOCTTY)
    if fd < 0 then
        return { pty = pty, error = "open failed" }
    end
    local ws = ffi.new("struct qpdf_winsize")
    local rc = ffi.C.ioctl(fd, TIOCGWINSZ, ws)
    ffi.C.close(fd)
    return { pty = pty, rc = rc, col = ws.col, row = ws.row, xpixel = ws.xpixel, ypixel = ws.ypixel }
end

-- The Hyprland window whose pid is an ancestor of this process.
local function window()
    local res = vim.system({ "hyprctl", "clients", "-j" }, { text = true }):wait()
    local ok, clients = pcall(vim.json.decode, res.stdout or "")
    if not ok then
        return { error = "hyprctl failed" }
    end
    local by_pid = {}
    for _, c in ipairs(clients) do
        by_pid[c.pid] = c
    end
    local pid = vim.fn.getpid()
    while pid and pid > 1 do
        local c = by_pid[pid]
        if c then
            return { class = c.class, size = c.size, at = c.at, pid = pid }
        end
        pid = parent(pid)
    end
    return { error = "no window found" }
end

local function finish()
    result.grid = { columns = vim.o.columns, lines = vim.o.lines }
    result.winsize = winsize()
    result.window = window()
    local f = assert(io.open(out, "w"))
    f:write(vim.json.encode(result))
    f:close()
    vim.cmd("qall!")
end

vim.api.nvim_create_autocmd("TermResponse", {
    callback = function(ev)
        table.insert(result.termresponse, ev.data.sequence)
    end,
})
vim.on_key(function(_, typed)
    if typed and typed ~= "" then
        table.insert(result.keys, typed)
    end
end)

vim.api.nvim_create_autocmd("UIEnter", {
    once = true,
    callback = function()
        -- Let the TUI settle (resize, its own queries) before asking.
        vim.defer_fn(function()
            -- CSI 16 t: cell size in px. CSI 14 t: text area size in px.
            vim.api.nvim_ui_send("\27[16t\27[14t")
            vim.defer_fn(finish, 700)
        end, 300)
    end,
})
