-- What the user sees inside Neovim while a PDF is open: the placeholder
-- buffer, the winbar and the buffer-local keymaps.

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

-- Ouvre le PDF de test (7 pages, terminal de 1920 pixels de large).
local function open_pdf(opts)
    helpers.fake_env(child, { QUICKPDF_FAKE_PAGES = 7, QUICKPDF_FAKE_TERM_WIDTH = 1920 })
    child.lua(
        [[
        require("quickpdf").setup(...)
        vim.cmd.edit("tests/fixtures/sample.pdf")
        ]],
        { opts or {} }
    )
end

-- Texte du winbar de la fenêtre courante.
local function winbar()
    return child.lua_get([[vim.wo[0].winbar]])
end

-- Numéro de page du tampon courant.
local function page()
    return child.lua_get([[vim.b.quickpdf.page]])
end

T["shows file name, page and zoom in the winbar"] = function()
    open_pdf()
    eq(winbar(), "📖 sample   page 1/7   zoom 100%%   n/p page · z/q zoom · e reset · hjkl pan")
end

T["follows a page turn in the winbar"] = function()
    open_pdf()
    child.lua([[require("quickpdf.viewer").actions.next_page(0)]])
    eq(winbar(), "📖 sample   page 2/7   zoom 100%%   n/p page · z/q zoom · e reset · hjkl pan")
end

T["follows a zoom step in the winbar"] = function()
    open_pdf()
    child.lua([[require("quickpdf.viewer").actions.zoom_in(0)]])
    eq(winbar(), "📖 sample   page 1/7   zoom 110%%   n/p page · z/q zoom · e reset · hjkl pan")
end

T["shows the configured keys in the winbar"] = function()
    open_pdf({ keymaps = { next_page = "<Down>", prev_page = "<Up>" } })
    eq(winbar(), "📖 sample   page 1/7   zoom 100%%   <Down>/<Up> page · z/q zoom · e reset · hjkl pan")
end

T["leaves the winbar empty when it is turned off"] = function()
    open_pdf({ winbar = false })
    eq(winbar(), "")
end

T["turns the PDF buffer into a read-only placeholder"] = function()
    open_pdf()
    eq(child.lua_get([[vim.bo.buftype]]), "nofile")
    eq(child.lua_get([[vim.bo.modifiable]]), false)
    eq(child.lua_get([[vim.bo.swapfile]]), false)
    local lines = child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]])
    eq(vim.tbl_contains(lines, "  📖 sample.pdf"), true)
end

T["turns the page with the configured key"] = function()
    open_pdf({ keymaps = { next_page = "<C-n>" } })
    child.type_keys("<C-n>")
    eq(page(), 2)
end

T["leaves a key disabled with false unmapped"] = function()
    open_pdf({ keymaps = { zoom_out = false } })
    eq(child.lua_get([[vim.fn.maparg("q", "n")]]), "")
end

return T
