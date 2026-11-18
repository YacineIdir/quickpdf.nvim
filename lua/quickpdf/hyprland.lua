-- Everything that talks to the compositor through `hyprctl`: finding the
-- terminal, waiting for the viewer window, placing it and handing focus back.

local process = require("quickpdf.process")

local M = {}

-- Must match `FloatingWindow.title` in quickshell/pdf_viewer/shell.qml.
M.TITLE = "quickshell-pdf-viewer"

local run = process.run

-- The window that has focus right now is the terminal running this nvim.
function M.active_window()
    local res = run({ "hyprctl", "activewindow", "-j" })
    if res.code ~= 0 then
        return nil
    end
    local ok, decoded = pcall(vim.json.decode, res.stdout)
    return ok and decoded or nil
end

-- The `open` IPC call only confirms QML received the message, not that the
-- Wayland surface has mapped. Dispatching resize/move/focus before it exists
-- silently no-ops, so poll for it. Every Neovim instance has a viewer with the
-- same title (the window rule matches it), so the window must also belong to
-- the daemon `pid`; with no pid known, the title alone decides.
function M.wait_for_viewer(pid, timeout_ms)
    local waited = 0
    while waited < timeout_ms do
        local res = run({ "hyprctl", "clients", "-j" })
        if res.code == 0 then
            local ok, clients = pcall(vim.json.decode, res.stdout)
            if ok then
                for _, c in ipairs(clients) do
                    if c.title == M.TITLE and (pid == nil or c.pid == pid) then
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

-- Fallback when the user has not installed the Hyprland windowrule.
function M.ensure_floating(viewer)
    if not viewer.floating then
        run({ "hyprctl", "dispatch", "togglefloating", "address:" .. viewer.address })
    end
end

-- Give the `viewer` window the exact position and size of `win`.
function M.cover(viewer, win)
    local x, y = win.at[1], win.at[2]
    local w, h = win.size[1], win.size[2]
    local target = "address:" .. viewer.address
    run({ "hyprctl", "dispatch", "resizewindowpixel", string.format("exact %d %d,%s", w, h, target) })
    run({ "hyprctl", "dispatch", "movewindowpixel", string.format("exact %d %d,%s", x, y, target) })
end

function M.focus(addr)
    if addr then
        run({ "hyprctl", "dispatch", "focuswindow", "address:" .. addr })
    end
end

return M
