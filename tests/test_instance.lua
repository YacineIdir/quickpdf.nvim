-- One daemon per Neovim instance (docs/adr/0002-one-daemon-per-neovim-instance.md):
-- each instance reaches Quickshell through a config path of its own, so its
-- daemon, IPC calls, stray cleanup and viewer window never touch another
-- instance's.

local MiniTest = require("mini.test")
local helpers = dofile("tests/helpers.lua")

local child = helpers.new_child_neovim()
local other = helpers.new_child_neovim()
local eq = MiniTest.expect.equality

local T = MiniTest.new_set({
    hooks = {
        pre_case = child.setup,
        post_once = function()
            child.stop()
            other.stop()
        end,
    },
})

-- Ouvre le PDF de test dans `c` alors qu'aucun démon ne tourne encore.
local function open_pdf(c, env)
    helpers.fake_env(c, vim.tbl_extend("force", { QUICKPDF_FAKE_DAEMON_DEAD = 1 }, env or {}))
    c.lua([[
        require("quickpdf").setup()
        vim.cmd.edit("tests/fixtures/sample.pdf")
    ]])
end

-- Déclenche dans `c` ce que fait Neovim en quittant.
local function leave(c)
    c.lua([[vim.api.nvim_exec_autocmds("VimLeavePre", {})]])
end

-- Le dossier de config Quickshell livré avec le plugin.
local function bundled_config()
    return child.lua_get([[require("quickpdf.config").options.qs_config]])
end

T["spawns its daemon on a config path of its own, linked to the bundled config"] = function()
    open_pdf(child)
    local path = helpers.config_paths(child)[1]
    eq(path == bundled_config(), false)
    eq(vim.uv.fs_realpath(path), vim.uv.fs_realpath(bundled_config()))
end

T["sends every quickshell call to that path, up to quitting"] = function()
    open_pdf(child)
    leave(child)
    local paths = helpers.config_paths(child)
    eq(vim.tbl_contains(helpers.calls(child, "quickshell")[#paths], "quit"), true)
    for _, path in ipairs(paths) do
        eq(path, paths[1])
    end
end

T["uses a different config path than another instance"] = function()
    other.setup()
    open_pdf(child)
    open_pdf(other)
    eq(helpers.config_paths(child)[1] == helpers.config_paths(other)[1], false)
end

T["looks for stray daemons of its own config path only"] = function()
    open_pdf(child)
    local path = helpers.config_paths(child)[1]
    eq(helpers.calls(child, "pgrep"), { { "pgrep", "-f", "quickshell -p " .. path } })
end

T["places its own viewer, not the one of another instance"] = function()
    open_pdf(child, { QUICKPDF_FAKE_OTHER_VIEWER = 1, QUICKPDF_FAKE_VIEWER_FLOATING = "false" })
    local targets = {}
    for _, call in ipairs(helpers.calls(child, "hyprctl")) do
        if call[2] == "dispatch" and call[3] ~= "focuswindow" then
            table.insert(targets, call[3] .. " " .. call[4]:match("[^,]*$"))
        end
    end
    eq(targets, {
        "togglefloating address:0x2000",
        "resizewindowpixel address:0x2000",
        "movewindowpixel address:0x2000",
    })
end

T["removes its config link on exit and keeps the bundled config"] = function()
    open_pdf(child)
    local path = helpers.config_paths(child)[1]
    leave(child)
    eq(vim.uv.fs_lstat(vim.fs.dirname(path)), nil)
    eq(vim.fn.filereadable(bundled_config() .. "/shell.qml"), 1)
end

T["leaves other daemons alone on exit when it never opened a PDF"] = function()
    child.lua([[require("quickpdf").setup()]])
    leave(child)
    eq(helpers.calls(child, "quickshell"), {})
    eq(helpers.calls(child, "pgrep"), {})
end

return T
