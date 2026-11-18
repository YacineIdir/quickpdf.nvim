-- Option merging: what `setup()` returns and what the other modules read from
-- `config.options`. Expected values come from the defaults documented in
-- README.md.

local MiniTest = require("mini.test")
local helpers = dofile("tests/helpers.lua")

local child = helpers.new_child_neovim()
local eq = MiniTest.expect.equality

local T = MiniTest.new_set({
    hooks = {
        pre_case = child.setup,
        post_once = child.stop,
    },
})

-- Appelle `config.setup(opts)` dans le Neovim enfant et renvoie les options.
local function setup(opts)
    return child.lua_get([[require("quickpdf.config").setup(...)]], { opts })
end

T["uses the documented defaults when no option is given"] = function()
    local options = setup()
    options.qs_config = nil
    eq(options, {
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
    })
end

T["points qs_config at the bundled Quickshell config"] = function()
    local qs_config = setup().qs_config
    eq(vim.fn.fnamemodify(qs_config, ":t"), "pdf_viewer")
    eq(vim.fn.filereadable(qs_config .. "/shell.qml"), 1)
end

T["keeps an explicit qs_config"] = function()
    eq(setup({ qs_config = "/tmp/my-viewer" }).qs_config, "/tmp/my-viewer")
end

T["keeps the other defaults when one keymap is overridden"] = function()
    local options = setup({ keymaps = { zoom_out = "Z" } })
    eq(options.keymaps.zoom_out, "Z")
    eq(options.keymaps.prev_page, "p")
    eq(options.zoom_step, 0.1)
end

T["keeps a keymap disabled with false"] = function()
    eq(setup({ keymaps = { zoom_out = false } }).keymaps.zoom_out, false)
end

T["forgets the options of a previous setup"] = function()
    setup({ zoom_step = 0.5, keymaps = { next_page = "J" } })
    local options = setup({})
    eq(options.zoom_step, 0.1)
    eq(options.keymaps.next_page, "n")
end

T["exposes the merged options to the other modules"] = function()
    setup({ zoom_step = 0.3 })
    eq(child.lua_get([[require("quickpdf.config").options.zoom_step]]), 0.3)
end

return T
