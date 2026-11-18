-- Tests of the harness itself: a headless child Neovim loads the plugin, the
-- fake executables on PATH record the exact command line they receive
-- (docs/adr/0004-fake-executables-instead-of-injection.md), and the documented
-- test command fails loudly.

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

T["loads the plugin in a headless child Neovim"] = function()
    child.lua([[require("quickpdf").setup()]])
    eq(child.lua_get([[type(require("quickpdf").show)]]), "function")
end

T["records the exact argument list a fake executable receives"] = function()
    child.lua([[require("quickpdf.process").run({ "pdfinfo", "/tmp/l'examen $(id) a.pdf" })]])
    eq(helpers.calls(child, "pdfinfo"), { { "pdfinfo", "/tmp/l'examen $(id) a.pdf" } })
end

T["exits non-zero when a case fails"] = function()
    local res = vim.system({ "make", "test", "TESTS=tests/fixtures/failing/test_fail.lua" }, { text = true }):wait()
    MiniTest.expect.no_equality(res.code, 0)
end

return T
