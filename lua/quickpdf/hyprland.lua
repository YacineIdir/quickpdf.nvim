-- Everything that talks to the compositor through `hyprctl`: finding the
-- terminal, waiting for the viewer window, placing it and handing focus back.

local process = require("quickpdf.process")

local M = {}

-- Must match `FloatingWindow.title` in quickshell/pdf_viewer/shell.qml.
M.TITLE = "quickshell-pdf-viewer"
local TITLE_REGEX = "^(" .. M.TITLE .. ")$"

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
-- silently no-ops, so poll for it.
function M.wait_for_viewer(timeout_ms)
    local waited = 0
    while waited < timeout_ms do
        local res = run({ "hyprctl", "clients", "-j" })
        if res.code == 0 then
            local ok, clients = pcall(vim.json.decode, res.stdout)
            if ok then
                for _, c in ipairs(clients) do
                    if c.title == M.TITLE then
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
function M.ensure_floating(client)
    if client and not client.floating then
        run({ "hyprctl", "dispatch", "togglefloating", "title:" .. TITLE_REGEX })
    end
end

-- Give the viewer the exact position and size of `win`.
function M.cover(win)
    local x, y = win.at[1], win.at[2]
    local w, h = win.size[1], win.size[2]
    run({ "hyprctl", "dispatch", "resizewindowpixel", string.format("exact %d %d,title:%s", w, h, TITLE_REGEX) })
    run({ "hyprctl", "dispatch", "movewindowpixel", string.format("exact %d %d,title:%s", x, y, TITLE_REGEX) })
end

function M.focus(addr)
    if addr then
        run({ "hyprctl", "dispatch", "focuswindow", "address:" .. addr })
    end
end

return M
