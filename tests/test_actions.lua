-- Page, zoom and pan actions: the navigation state they leave in
-- `vim.b[buf].quickpdf` and the IPC command line they send to Quickshell.

local MiniTest = require("mini.test")
local helpers = dofile("tests/helpers.lua")

local child = helpers.new_child_neovim()
local eq = MiniTest.expect.equality

local TERM_WIDTH = 1920
local TERM_HEIGHT = 1080
local PAGES = 7

local T = MiniTest.new_set({
    hooks = {
        pre_case = child.setup,
        post_once = child.stop,
    },
})

-- Ouvre le PDF de test dans le Neovim enfant et renvoie son numéro de tampon.
local function open_pdf(opts)
    helpers.fake_env(child, {
        QUICKPDF_FAKE_PAGES = PAGES,
        QUICKPDF_FAKE_TERM_WIDTH = TERM_WIDTH,
        QUICKPDF_FAKE_TERM_HEIGHT = TERM_HEIGHT,
    })
    return child.lua_get(
        [[
        local options = ...
        require("quickpdf").setup(options)
        vim.cmd.edit("tests/fixtures/sample.pdf")
        return vim.api.nvim_get_current_buf()
        ]],
        { opts or {} }
    )
end

-- Déclenche l'action `name` sur le tampon `buf`.
local function act(buf, name, times)
    child.lua(
        [[
        local buf, name, times = ...
        for _ = 1, times do
            require("quickpdf.viewer").actions[name](buf)
        end
        ]],
        { buf, name, times or 1 }
    )
end

-- Renvoie les arguments de la dernière fonction IPC `fn` appelée, après
-- `call pdf <fn>` sur la ligne de commande de Quickshell.
local function last_ipc(fn)
    local args = nil
    for _, argv in ipairs(helpers.calls(child, "quickshell")) do
        for i, arg in ipairs(argv) do
            if arg == "call" and argv[i + 1] == "pdf" and argv[i + 2] == fn then
                args = vim.list_slice(argv, i + 3)
            end
        end
    end
    return args
end

-- État de navigation du tampon.
local function state(buf)
    return child.lua_get([[vim.b[...].quickpdf]], { buf })
end

T["opens on page 1 of the page count reported by pdfinfo"] = function()
    local buf = open_pdf()
    eq(state(buf).page, 1)
    eq(state(buf).total, PAGES)
end

T["next_page advances one page and renders it at the window width"] = function()
    local buf = open_pdf()
    act(buf, "next_page")
    eq(state(buf).page, 2)
    eq(last_ipc("gotoPage"), { "2", tostring(TERM_WIDTH) })
end

T["next_page stops on the last page"] = function()
    local buf = open_pdf()
    act(buf, "next_page", PAGES + 3)
    eq(state(buf).page, PAGES)
    eq(last_ipc("gotoPage"), { tostring(PAGES), tostring(TERM_WIDTH) })
end

T["prev_page stops on the first page"] = function()
    local buf = open_pdf()
    act(buf, "prev_page", 2)
    eq(state(buf).page, 1)
    eq(last_ipc("gotoPage"), { "1", tostring(TERM_WIDTH) })
end

T["zoom_in renders wider by one zoom step"] = function()
    local buf = open_pdf()
    act(buf, "zoom_in")
    eq(last_ipc("gotoPage"), { "1", "2112" })
end

T["zoom_out renders narrower by one zoom step"] = function()
    local buf = open_pdf()
    act(buf, "zoom_out")
    eq(last_ipc("gotoPage"), { "1", "1728" })
end

T["zoom_out stops at the configured minimum zoom"] = function()
    local buf = open_pdf({ min_zoom = 0.5 })
    act(buf, "zoom_out", 20)
    eq(last_ipc("gotoPage"), { "1", "960" })
end

T["zoom_reset renders at the window width again"] = function()
    local buf = open_pdf()
    act(buf, "zoom_in", 3)
    act(buf, "zoom_reset")
    eq(last_ipc("gotoPage"), { "1", tostring(TERM_WIDTH) })
end

T["pan_right scrolls by the configured share of the window"] = function()
    local buf = open_pdf()
    act(buf, "pan_right")
    eq(last_ipc("pan"), { "480", "0" })
end

T["pan_up scrolls up by the configured share of the window"] = function()
    local buf = open_pdf()
    act(buf, "pan_up")
    eq(last_ipc("pan"), { "0", "-270" })
end

return T
