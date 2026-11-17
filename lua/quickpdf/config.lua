-- User options. Every other module reads `require("quickpdf.config").options`,
-- which setup() replaces with the merged table.

local M = {}

-- The Quickshell config ships inside this repo; locate it relative to this file.
local function default_qs_config()
    local src = debug.getinfo(1, "S").source:sub(2)
    return vim.fn.fnamemodify(src, ":h:h:h") .. "/quickshell/pdf_viewer"
end

M.defaults = {
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

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
    M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
    M.options.qs_config = M.options.qs_config or default_qs_config()
    return M.options
end

return M
