-- Navigation state of a PDF buffer (page/zoom) and the glue that keeps the
-- Quickshell window in sync with it. State lives in `vim.b[buf].quickpdf`:
-- { path, page, total, scale, term_addr, width, height }.

local config = require("quickpdf.config")
local daemon = require("quickpdf.daemon")
local hyprland = require("quickpdf.hyprland")
local process = require("quickpdf.process")
local ui = require("quickpdf.ui")

local M = {}

local function page_count(path)
    local res = process.run({ "pdfinfo", path })
    if res.code == 0 then
        local n = res.stdout:match("Pages:%s*(%d+)")
        if n then
            return tonumber(n)
        end
    end
    return 1
end

local function target_width(st)
    return math.floor((st.width or 900) * st.scale)
end

local function render(buf)
    local st = vim.b[buf].quickpdf
    daemon.call("gotoPage", st.page, target_width(st))
    hyprland.focus(st.term_addr)
    ui.winbar(buf, st)
end

-- Show the viewer over the terminal for `buf`, spawning the daemon if needed.
function M.show(buf)
    local st = vim.b[buf].quickpdf
    if not st then
        return
    end
    daemon.ensure()
    local win = hyprland.active_window()
    if win then
        st.term_addr = win.address
        st.width = win.size[1]
        st.height = win.size[2]
        vim.b[buf].quickpdf = st
    end
    daemon.call("open", st.path, st.page, target_width(st))
    local qs = hyprland.wait_for_viewer(1500)
    if not qs then
        -- Daemon alive but its window was destroyed (closed via the WM):
        -- `open` just toggles visibility on a dead window. Respawn, retry once.
        daemon.restart()
        daemon.call("open", st.path, st.page, target_width(st))
        qs = hyprland.wait_for_viewer(1500)
    end
    hyprland.ensure_floating(qs)
    if win then
        hyprland.cover(win)
    end
    hyprland.focus(st.term_addr)
    -- Without the `no_focus` windowrule Hyprland hands focus to the new
    -- toplevel a beat after mapping; reassert a few times to win that race.
    for _, delay in ipairs({ 150, 400, 800 }) do
        vim.defer_fn(function()
            hyprland.focus(st.term_addr)
        end, delay)
    end
    ui.winbar(buf, st)
end

function M.hide()
    if daemon.alive() then
        daemon.call("close")
    end
end

local function update(buf, f)
    local st = vim.b[buf].quickpdf
    f(st)
    vim.b[buf].quickpdf = st
    render(buf)
end

-- Pan is not part of the buffer state: QML owns the scroll position.
local function pan(buf, dx, dy)
    local st = vim.b[buf].quickpdf
    local frac = config.options.pan_fraction
    daemon.call("pan", math.floor(dx * (st.width or 900) * frac), math.floor(dy * (st.height or 700) * frac))
end

-- One entry per key of `config.options.keymaps`.
M.actions = {
    next_page = function(buf)
        update(buf, function(st)
            st.page = math.min(st.total, st.page + 1)
        end)
    end,
    prev_page = function(buf)
        update(buf, function(st)
            st.page = math.max(1, st.page - 1)
        end)
    end,
    zoom_in = function(buf)
        update(buf, function(st)
            st.scale = st.scale + config.options.zoom_step
        end)
    end,
    zoom_out = function(buf)
        update(buf, function(st)
            st.scale = math.max(config.options.min_zoom, st.scale - config.options.zoom_step)
        end)
    end,
    zoom_reset = function(buf)
        update(buf, function(st)
            st.scale = 1.0
        end)
    end,
    pan_left = function(buf)
        pan(buf, -1, 0)
    end,
    pan_right = function(buf)
        pan(buf, 1, 0)
    end,
    pan_up = function(buf)
        pan(buf, 0, -1)
    end,
    pan_down = function(buf)
        pan(buf, 0, 1)
    end,
}

-- Take over a freshly read *.pdf buffer and show it.
function M.attach(buf)
    -- Not `expand("%:p")`: when a file explorer loads the buffer via
    -- nvim_win_set_buf, `%` may still point at the explorer buffer.
    local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":p")
    ui.placeholder(buf, path)
    vim.b[buf].quickpdf = { path = path, page = 1, total = page_count(path), scale = 1.0 }
    ui.keymaps(buf, M.actions)
    M.show(buf)
end

return M
