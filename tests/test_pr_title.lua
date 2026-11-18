-- The pull request title check run by CI (.github/scripts/check-pr-title.sh).
-- Squash merges turn the title into the commit message release-please reads
-- (docs/adr/0005-branching-merging-and-releases.md), so it must follow
-- Conventional Commits.

local MiniTest = require("mini.test")

local eq = MiniTest.expect.equality

local SCRIPT = ".github/scripts/check-pr-title.sh"

-- Code de sortie du script pour `title`.
local function check(title)
    return vim.system({ SCRIPT, title }, { text = true }):wait().code
end

local T = MiniTest.new_set()

T["accepts"] = MiniTest.new_set({
    parametrize = {
        { "fix(daemon): run one daemon per Neovim instance" },
        { "test: add a headless test harness with fake executables on PATH" },
        { "chore(ci): add lint workflow" },
        { "feat!: drop Neovim 0.9" },
        { "refactor(process)!: rename spawn" },
        { "docs(adr): mark 0002 implemented" },
    },
})

T["accepts"]["a Conventional Commits title"] = function(title)
    eq(check(title), 0)
end

T["rejects"] = MiniTest.new_set({
    parametrize = {
        { "Add lint workflow" },
        { "feature: unknown type" },
        { "Fix(daemon): capitalised type" },
        { "fix(daemon) missing colon" },
        { "fix:no space after the colon" },
        { "fix: " },
        { "fix(): empty scope" },
        { "" },
    },
})

T["rejects"]["any other title"] = function(title)
    eq(check(title), 1)
end

T["tells what a valid title looks like"] = function()
    local res = vim.system({ SCRIPT, "Add lint workflow" }, { text = true }):wait()
    eq(res.stderr:find("<type>(<scope>): <description>", 1, true) ~= nil, true)
end

return T
