-- What the user sees inside Neovim: the placeholder buffer, the winbar and
-- the buffer-local keymaps. Knows nothing about Quickshell or Hyprland.

local config = require("quickpdf.config")

local M = {}

-- Turn the PDF buffer into a read-only placeholder.
function M.placeholder(buf, path)
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
end

-- Map each configured key to `actions[name](buf)`. A false or "" key is skipped.
function M.keymaps(buf, actions)
    for action, key in pairs(config.options.keymaps) do
        if key and key ~= "" then
            vim.keymap.set("n", key, function()
                actions[action](buf)
            end, { buffer = buf, desc = "quickpdf: " .. action })
        end
    end
end

function M.winbar(buf, st)
    if not config.options.winbar then
        return
    end
    local win = vim.fn.bufwinid(buf)
    if not st or win == -1 then
        return
    end
    local k = config.options.keymaps
    vim.wo[win].winbar = string.format(
        "📖 %s   page %d/%d   zoom %.0f%%%%   %s/%s page · %s/%s zoom · %s reset · %s%s%s%s pan",
        vim.fn.fnamemodify(st.path, ":t:r"),
        st.page,
        st.total,
        st.scale * 100,
        k.next_page,
        k.prev_page,
        k.zoom_in,
        k.zoom_out,
        k.zoom_reset,
        k.pan_left,
        k.pan_down,
        k.pan_up,
        k.pan_right
    )
end

return M
