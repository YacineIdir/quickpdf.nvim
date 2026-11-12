-- quickpdf.nvim: view PDFs from Neovim in a Quickshell window that overlays
-- the terminal, positioned by Hyprland. Neovim owns navigation state
-- (page/zoom/pan) and drives a persistent Quickshell daemon over its IPC.
--
-- Why not in-buffer kitty graphics: any layout change after the image is
-- placed (winbar, cmdheight, number column) invalidates the placement and
-- the page flickers away. A real compositor window sidesteps that.

local M = {}

local TITLE = "quickshell-pdf-viewer"
local TITLE_REGEX = "^(" .. TITLE .. ")$"

-- The Quickshell config ships inside this repo; locate it relative to this file.
local function default_qs_config()
    local src = debug.getinfo(1, "S").source:sub(2)
    return vim.fn.fnamemodify(src, ":h:h:h") .. "/quickshell/pdf_viewer"
end

M.config = {
    qs_config = nil, -- path to a dir containing shell.qml; defaults to the bundled one
    keymaps = {
        next_page = "n",
        prev_page = "p",
        zoom_in = "z",
        zoom_out = "q",
        zoom_reset = "e",
        pan_left = "h",
        pan_right = "l",
        pan_up = "k",
        pan_down = "j",
    },
    zoom_step = 0.1,
    min_zoom = 0.2,
    pan_fraction = 0.25,
    winbar = true,
}

local daemon_checked = false

local function run(cmd)
    return vim.system(cmd, { text = true }):wait()
end

local function ipc_call(fn, ...)
    local args = { "quickshell", "ipc", "-p", M.config.qs_config, "call", "pdf", fn }
    for _, a in ipairs({ ... }) do
        table.insert(args, tostring(a))
    end
    return run(args)
end

local function daemon_alive()
    return run({ "quickshell", "ipc", "-p", M.config.qs_config, "show" }).code == 0
end

-- `quickshell ipc` refuses to pick an instance when two of the same config
-- run, so a duplicate makes every call fail and daemon_alive() report dead,
-- which would spawn a third. Kill strays before spawning, and spawn with -n.
-- pgrep -f matches any cmdline containing the pattern (a shell, this nvim),
-- so only keep pids whose comm is really the quickshell binary.
local function stray_pids()
    local res = run({ "pgrep", "-f", "quickshell -p " .. M.config.qs_config })
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

local function ensure_daemon()
    if daemon_checked and daemon_alive() then
        return
    end
    if daemon_alive() then
        daemon_checked = true
        return
    end
    kill_strays()
    vim.system({ "quickshell", "-p", M.config.qs_config, "-d", "-n" }, { detach = true })
    for _ = 1, 20 do
        if daemon_alive() then
            daemon_checked = true
            return
        end
        vim.uv.sleep(100)
    end
    vim.notify("quickpdf: Quickshell daemon did not come up", vim.log.levels.ERROR)
end

local function restart_daemon()
    if daemon_alive() then
        ipc_call("quit")
        for _ = 1, 10 do
            if not daemon_alive() then
                break
            end
            vim.uv.sleep(100)
        end
    end
    daemon_checked = false
    ensure_daemon()
end

-- The window that has focus right now is the terminal running this nvim.
local function active_window()
    local res = run({ "hyprctl", "activewindow", "-j" })
    if res.code ~= 0 then
        return nil
    end
    local ok, decoded = pcall(vim.json.decode, res.stdout)
    return ok and decoded or nil
end

local function sync_geometry(win)
    local x, y = win.at[1], win.at[2]
    local w, h = win.size[1], win.size[2]
    run({ "hyprctl", "dispatch", "resizewindowpixel", string.format("exact %d %d,title:%s", w, h, TITLE_REGEX) })
    run({ "hyprctl", "dispatch", "movewindowpixel", string.format("exact %d %d,title:%s", x, y, TITLE_REGEX) })
end

local function refocus(addr)
    if addr then
        run({ "hyprctl", "dispatch", "focuswindow", "address:" .. addr })
    end
end

-- The `open` IPC call only confirms QML received the message, not that the
-- Wayland surface has mapped. Dispatching resize/move/focus before it exists
-- silently no-ops, so poll for it.
local function wait_for_qs_window(timeout_ms)
    local waited = 0
    while waited < timeout_ms do
        local res = run({ "hyprctl", "clients", "-j" })
        if res.code == 0 then
            local ok, clients = pcall(vim.json.decode, res.stdout)
            if ok then
                for _, c in ipairs(clients) do
                    if c.title == TITLE then
                        return c
                    end
                end
            end
        end
        vim.uv.sleep(50)
        waited = waited + 50
    end
    return nil
end

local function page_count(path)
    local res = run({ "pdfinfo", path })
    if res.code == 0 then
        local n = res.stdout:match("Pages:%s*(%d+)")
        if n then
            return tonumber(n)
        end
    end
    return 1
end

local function set_winbar(buf)
    if not M.config.winbar then
        return
    end
    local st = vim.b[buf].quickpdf
    local win = vim.fn.bufwinid(buf)
    if not st or win == -1 then
        return
    end
    local k = M.config.keymaps
    vim.wo[win].winbar = string.format(
        "📖 %s   page %d/%d   zoom %.0f%%%%   %s/%s page · %s/%s zoom · %s reset · %s%s%s%s pan",
        vim.fn.fnamemodify(st.path, ":t:r"),
        st.page,
        st.total,
        st.scale * 100,
        k.next_page, k.prev_page, k.zoom_in, k.zoom_out, k.zoom_reset,
        k.pan_left, k.pan_down, k.pan_up, k.pan_right
    )
end

local function target_width(st)
    return math.floor((st.width or 900) * st.scale)
end

local function render(buf)
    local st = vim.b[buf].quickpdf
    ipc_call("gotoPage", st.page, target_width(st))
    refocus(st.term_addr)
    set_winbar(buf)
end

function M.show(buf)
    local st = vim.b[buf].quickpdf
    if not st then
        return
    end
    ensure_daemon()
    local win = active_window()
    if win then
        st.term_addr = win.address
        st.width = win.size[1]
        st.height = win.size[2]
        vim.b[buf].quickpdf = st
    end
    ipc_call("open", st.path, st.page, target_width(st))
    local qs = wait_for_qs_window(1500)
    if not qs then
        -- Daemon alive but its window was destroyed (closed via the WM):
        -- `open` just toggles visibility on a dead window. Respawn, retry once.
        restart_daemon()
        ipc_call("open", st.path, st.page, target_width(st))
        qs = wait_for_qs_window(1500)
    end
    -- Fallback when the user has not installed the Hyprland windowrule.
    if qs and not qs.floating then
        run({ "hyprctl", "dispatch", "togglefloating", "title:" .. TITLE_REGEX })
    end
    if win then
        sync_geometry(win)
    end
    refocus(st.term_addr)
    -- Without the `no_focus` windowrule Hyprland hands focus to the new
    -- toplevel a beat after mapping; reassert a few times to win that race.
    for _, delay in ipairs({ 150, 400, 800 }) do
        vim.defer_fn(function()
            refocus(st.term_addr)
        end, delay)
    end
    set_winbar(buf)
end

function M.hide()
    if daemon_alive() then
        ipc_call("close")
    end
end

local function update(buf, f)
    local st = vim.b[buf].quickpdf
    f(st)
    vim.b[buf].quickpdf = st
    render(buf)
end

local actions = {
    next_page = function(buf)
        update(buf, function(st) st.page = math.min(st.total, st.page + 1) end)
    end,
    prev_page = function(buf)
        update(buf, function(st) st.page = math.max(1, st.page - 1) end)
    end,
    zoom_in = function(buf)
        update(buf, function(st) st.scale = st.scale + M.config.zoom_step end)
    end,
    zoom_out = function(buf)
        update(buf, function(st) st.scale = math.max(M.config.min_zoom, st.scale - M.config.zoom_step) end)
    end,
    zoom_reset = function(buf)
        update(buf, function(st) st.scale = 1.0 end)
    end,
}

local function pan(buf, dx, dy)
    local st = vim.b[buf].quickpdf
    local frac = M.config.pan_fraction
    ipc_call("pan", math.floor(dx * (st.width or 900) * frac), math.floor(dy * (st.height or 700) * frac))
end
actions.pan_left = function(buf) pan(buf, -1, 0) end
actions.pan_right = function(buf) pan(buf, 1, 0) end
actions.pan_up = function(buf) pan(buf, 0, -1) end
actions.pan_down = function(buf) pan(buf, 0, 1) end

local function attach(buf)
    -- Not `expand("%:p")`: when a file explorer loads the buffer via
    -- nvim_win_set_buf, `%` may still point at the explorer buffer.
    local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":p")

    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "",
        "  📖 " .. vim.fn.fnamemodify(path, ":t"),
        "",
        "  Shown in the Quickshell window overlaying this terminal.",
    })
    vim.bo[buf].modifiable = false
    vim.bo[buf].modified = false
    vim.wo.number = false
    vim.wo.relativenumber = false

    vim.b[buf].quickpdf = { path = path, page = 1, total = page_count(path), scale = 1.0 }

    for action, key in pairs(M.config.keymaps) do
        if key and key ~= "" then
            vim.keymap.set("n", key, function()
                actions[action](buf)
            end, { buffer = buf, desc = "quickpdf: " .. action })
        end
    end

    M.show(buf)
end

function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})
    M.config.qs_config = M.config.qs_config or default_qs_config()

    local group = vim.api.nvim_create_augroup("quickpdf", { clear = true })

    vim.api.nvim_create_autocmd("BufReadCmd", {
        pattern = "*.pdf",
        group = group,
        callback = function(ev)
            attach(ev.buf)
        end,
    })

    vim.api.nvim_create_autocmd("BufEnter", {
        pattern = "*.pdf",
        group = group,
        callback = function(ev)
            if vim.b[ev.buf].quickpdf then
                M.show(ev.buf)
            end
        end,
    })

    vim.api.nvim_create_autocmd("BufLeave", {
        pattern = "*.pdf",
        group = group,
        callback = function(ev)
            if vim.b[ev.buf].quickpdf then
                M.hide()
            end
        end,
    })

    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
            if daemon_alive() then
                ipc_call("quit")
            end
            kill_strays()
        end,
    })
end

return M
