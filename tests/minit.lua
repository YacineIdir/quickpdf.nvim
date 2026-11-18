-- Minimal init for the test suite: the plugin and mini.test on the
-- runtimepath, and collection limited to `tests/test_*.lua` so fixtures under
-- `tests/fixtures/` only run when named explicitly.

local root = vim.fn.getcwd()

vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(root .. "/deps/mini.nvim")
vim.opt.packpath = ""

-- Liste les fichiers de tests collectés par `MiniTest.run()`.
local function find_files()
    return vim.fn.globpath("tests", "test_*.lua", true, true)
end

require("mini.test").setup({ collect = { find_files = find_files } })
