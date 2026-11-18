-- What opening a PDF sends to the outside world: the pdfinfo query, the IPC
-- calls to Quickshell and the hyprctl dispatches that place the viewer over
-- the terminal.

local MiniTest = require("mini.test")
local helpers = dofile("tests/helpers.lua")

local child = helpers.new_child_neovim()
local eq = MiniTest.expect.equality

local TITLE_MATCH = "title:^(quickshell-pdf-viewer)$"
local TERM_ADDRESS = "0xdeadbeef"
local TERM_WIDTH = 1600
local TERM_HEIGHT = 900
local TERM_X = 120
local TERM_Y = 40

local T = MiniTest.new_set({
    hooks = {
        pre_case = child.setup,
        post_once = child.stop,
    },
})

-- Ouvre le PDF de test dans le Neovim enfant et renvoie son chemin absolu.
local function open_pdf(env)
    helpers.fake_env(
        child,
        vim.tbl_extend("force", {
            QUICKPDF_FAKE_PAGES = 7,
            QUICKPDF_FAKE_TERM_ADDRESS = TERM_ADDRESS,
            QUICKPDF_FAKE_TERM_WIDTH = TERM_WIDTH,
            QUICKPDF_FAKE_TERM_HEIGHT = TERM_HEIGHT,
            QUICKPDF_FAKE_TERM_X = TERM_X,
            QUICKPDF_FAKE_TERM_Y = TERM_Y,
        }, env or {})
    )
    child.lua([[
        require("quickpdf").setup()
        vim.cmd.edit("tests/fixtures/sample.pdf")
    ]])
    return child.lua_get([[vim.fn.fnamemodify("tests/fixtures/sample.pdf", ":p")]])
end

-- Vrai si `argv` est l'un des appels enregistrés pour `program`.
local function called(program, argv)
    for _, call in ipairs(helpers.calls(child, program)) do
        if vim.deep_equal(call, argv) then
            return true
        end
    end
    return false
end

T["asks pdfinfo for the page count of the file being opened"] = function()
    local path = open_pdf()
    eq(helpers.calls(child, "pdfinfo"), { { "pdfinfo", path } })
end

T["tells Quickshell to open the file on page 1 at the window width"] = function()
    local path = open_pdf()
    local qs_config = child.lua_get([[require("quickpdf.config").options.qs_config]])
    eq(
        called("quickshell", {
            "quickshell",
            "ipc",
            "-p",
            qs_config,
            "call",
            "pdf",
            "open",
            path,
            "1",
            tostring(TERM_WIDTH),
        }),
        true
    )
end

T["sizes and moves the viewer onto the terminal window"] = function()
    open_pdf()
    eq(
        called("hyprctl", {
            "hyprctl",
            "dispatch",
            "resizewindowpixel",
            string.format("exact %d %d,%s", TERM_WIDTH, TERM_HEIGHT, TITLE_MATCH),
        }),
        true
    )
    eq(
        called("hyprctl", {
            "hyprctl",
            "dispatch",
            "movewindowpixel",
            string.format("exact %d %d,%s", TERM_X, TERM_Y, TITLE_MATCH),
        }),
        true
    )
end

T["hands keyboard focus back to the terminal"] = function()
    open_pdf()
    eq(called("hyprctl", { "hyprctl", "dispatch", "focuswindow", "address:" .. TERM_ADDRESS }), true)
end

T["leaves a floating viewer alone"] = function()
    open_pdf()
    eq(called("hyprctl", { "hyprctl", "dispatch", "togglefloating", TITLE_MATCH }), false)
end

T["floats the viewer when the window rule is missing"] = function()
    open_pdf({ QUICKPDF_FAKE_VIEWER_FLOATING = "false" })
    eq(called("hyprctl", { "hyprctl", "dispatch", "togglefloating", TITLE_MATCH }), true)
end

T["spawns one detached daemon when none answers IPC"] = function()
    open_pdf({ QUICKPDF_FAKE_DAEMON_DEAD = 1 })
    local qs_config = child.lua_get([[require("quickpdf.config").options.qs_config]])
    local spawns = {}
    for _, call in ipairs(helpers.calls(child, "quickshell")) do
        if call[2] ~= "ipc" then
            table.insert(spawns, call)
        end
    end
    eq(spawns, { { "quickshell", "-p", qs_config, "-d", "-n" } })
end

T["does not spawn a daemon when one already answers IPC"] = function()
    open_pdf()
    for _, call in ipairs(helpers.calls(child, "quickshell")) do
        eq(call[2], "ipc")
    end
end

return T
