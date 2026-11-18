-- quickpdf.nvim: view PDFs from Neovim in a Quickshell window that overlays
-- the terminal, positioned by Hyprland. Neovim owns navigation state
-- (page/zoom/pan) and drives a persistent Quickshell daemon over its IPC.
--
-- Why not in-buffer kitty graphics: any layout change after the image is
-- placed (winbar, cmdheight, number column) invalidates the placement and
-- the page flickers away. A real compositor window sidesteps that.
--
-- Module map:
--   config    user options
--   viewer    per-buffer navigation state, keeps the window in sync
--   ui        placeholder buffer, winbar, keymaps
--   daemon    Quickshell process lifecycle + IPC
--   hyprland  hyprctl calls (geometry, focus)
--   process   the only place that runs external programs

local config = require("quickpdf.config")
local daemon = require("quickpdf.daemon")
local viewer = require("quickpdf.viewer")

local M = {}

M.config = config.options
M.show = viewer.show
M.hide = viewer.hide

function M.setup(opts)
    M.config = config.setup(opts)

    local group = vim.api.nvim_create_augroup("quickpdf", { clear = true })

    vim.api.nvim_create_autocmd("BufReadCmd", {
        pattern = "*.pdf",
        group = group,
        callback = function(ev)
            viewer.attach(ev.buf)
        end,
    })

    vim.api.nvim_create_autocmd("BufEnter", {
        pattern = "*.pdf",
        group = group,
        callback = function(ev)
            if vim.b[ev.buf].quickpdf then
                viewer.show(ev.buf)
            end
        end,
    })

    vim.api.nvim_create_autocmd("BufLeave", {
        pattern = "*.pdf",
        group = group,
        callback = function(ev)
            if vim.b[ev.buf].quickpdf then
                viewer.hide()
            end
        end,
    })

    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = daemon.stop,
    })
end

return M
