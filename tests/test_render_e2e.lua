-- End-to-end rendering: the real plugin drives the real Quickshell daemon
-- (headless, QT_QPA_PLATFORM=offscreen) and the real pdftoppm. Only hyprctl
-- stays fake. Recording wrappers for `sh`, `pdftoppm` and `quickshell` sit
-- first on PATH. Skipped when quickshell or poppler-utils is not installed.

local MiniTest = require("mini.test")
local helpers = dofile("tests/helpers.lua")

local child = MiniTest.new_child_neovim()
local other = MiniTest.new_child_neovim()
local eq = MiniTest.expect.equality

local ROOT = vim.fn.getcwd()
local FAKES_DIR = ROOT .. "/tests/fakes"
local PAGES_PDF = ROOT .. "/tests/fixtures/pages.pdf"
-- Terminal width reported by the fake hyprctl, so the expected image width.
local WIDTH = 613
-- Quotes, spaces and a command substitution: the shell would have run it.
local HOSTILE_NAME = [[l'examen "final" $(touch $QUICKPDF_PWNED) v'2.pdf]]

-- Dossier propre au cas : wrappers, XDG_RUNTIME_DIR, PDF ouverts.
local tmp
-- Neovim enfants démarrés pendant le cas.
local started = {}

-- Écrit un script exécutable `name` dans `<tmp>/bin`.
local function write_script(name, lines)
    local path = tmp .. "/bin/" .. name
    vim.fn.writefile(vim.list_extend({ "#!/usr/bin/env bash" }, lines), path)
    vim.uv.fs_chmod(path, tonumber("755", 8))
end

-- Écrit un wrapper qui enregistre l'appel, exécute `before`, puis lance le
-- vrai programme.
local function write_recorder(program, before)
    local lines = { "source " .. vim.fn.shellescape(FAKES_DIR .. "/_record.sh"), 'quickpdf_record "$@"' }
    vim.list_extend(lines, before or {})
    table.insert(lines, "exec " .. vim.fn.exepath(program) .. ' "$@"')
    write_script(program, lines)
end

-- Envoie un appel IPC au démon de `c`, sur le chemin de config que `c` a
-- passé à quickshell. Quickshell ne trouve une instance que sur le même
-- affichage : environnement vidé, sans WAYLAND_DISPLAY ni DISPLAY, comme le
-- démon.
local function ipc(c, ...)
    local cmd = vim.list_extend({ "quickshell", "ipc", "-p", helpers.config_paths(c)[1], "call", "pdf" }, { ... })
    local env = { PATH = vim.env.PATH, HOME = vim.env.HOME, XDG_RUNTIME_DIR = tmp .. "/run" }
    return vim.system(cmd, { env = env, clear_env = true, text = true }):wait()
end

-- Page affichée par le visualiseur de `c` et largeur de l'image chargée.
local function shown(c)
    local page, img = (ipc(c, "info").stdout or ""):match("page=(%d+) target=%d+ img=(%d+)")
    return { page = tonumber(page), img = tonumber(img) }
end

-- Attend jusqu'à 5 s que le visualiseur de `c` affiche `expected`, puis
-- renvoie ce qu'il affiche.
local function wait_shown(c, expected)
    vim.wait(5000, function()
        return vim.deep_equal(shown(c), expected)
    end, 100)
    return shown(c)
end

-- Copie le PDF de test sous `name` et l'ouvre dans `c`. Renvoie son chemin
-- absolu.
local function open(c, name)
    local path = tmp .. "/work/" .. name
    assert(vim.uv.fs_copyfile(PAGES_PDF, path))
    c.lua([[vim.cmd.edit(vim.fn.fnameescape(...))]], { path })
    return path
end

-- Déclenche dans `c` ce que fait Neovim en quittant.
local function leave(c)
    c.lua([[vim.api.nvim_exec_autocmds("VimLeavePre", {})]])
end

-- Pages demandées à pdftoppm par `c`, dans l'ordre des rendus.
local function rendered_pages(c)
    return vim.tbl_map(function(argv)
        for i, arg in ipairs(argv) do
            if arg == "-f" then
                return argv[i + 1]
            end
        end
    end, helpers.calls(c, "pdftoppm"))
end

-- Démarre `c` avec le plugin configuré, dans l'environnement du cas.
local function start(c)
    c.restart({ "--noplugin", "-u", "tests/minit.lua" })
    c.lua(
        [[
        local tmp, width, log = ...
        vim.env.PATH = tmp .. "/bin:" .. vim.env.PATH
        vim.env.QUICKPDF_CALL_LOG = log
        vim.env.QUICKPDF_PWNED = tmp .. "/pwned"
        vim.env.QUICKPDF_FAKE_TERM_WIDTH = tostring(width)
        vim.env.XDG_RUNTIME_DIR = tmp .. "/run"
        vim.env.QT_QPA_PLATFORM = "offscreen"
        vim.env.WAYLAND_DISPLAY = nil
        vim.env.DISPLAY = nil
        vim.env.HYPRLAND_INSTANCE_SIGNATURE = nil
        vim.fn.chdir(tmp .. "/work")
        require("quickpdf").setup()
        ]],
        { tmp, WIDTH, vim.fn.tempname() }
    )
    table.insert(started, c)
end

local function setup()
    for _, program in ipairs({ "quickshell", "pdftoppm", "pdfinfo" }) do
        if vim.fn.executable(program) == 0 then
            MiniTest.skip(program .. " is not installed")
        end
    end

    tmp = vim.fn.tempname()
    for _, dir in ipairs({ "bin", "run", "work" }) do
        vim.fn.mkdir(tmp .. "/" .. dir, "p", tonumber("700", 8))
    end
    -- The fake lists one viewer window per running Quickshell process.
    write_script("hyprctl", {
        'export QUICKPDF_FAKE_VIEWER_PIDS="$(pgrep -x quickshell | tr "\\n" " ")"',
        "exec " .. vim.fn.shellescape(FAKES_DIR .. "/hyprctl") .. ' "$@"',
    })
    write_recorder("sh")
    write_recorder("quickshell")
    write_recorder("pdftoppm", { 'sleep "${QUICKPDF_E2E_RENDER_DELAY:-0}"' })

    start(child)
end

local function teardown()
    -- Quit the way Neovim does: the daemons outlive the child Neovim.
    for _, c in ipairs(started) do
        pcall(leave, c)
    end
    started = {}
    if tmp then
        vim.fn.delete(tmp, "rf")
        tmp = nil
    end
end

local T = MiniTest.new_set({
    hooks = {
        pre_case = setup,
        post_case = teardown,
        post_once = function()
            child.stop()
            other.stop()
        end,
    },
})

T["renders a PDF whose name has quotes, spaces and $(...)"] = function()
    local path = open(child, HOSTILE_NAME)
    eq(wait_shown(child, { page = 1, img = WIDTH }), { page = 1, img = WIDTH })
    eq(vim.tbl_contains(helpers.calls(child, "pdftoppm")[1], path), true)
end

T["never runs a command written in the file name"] = function()
    open(child, HOSTILE_NAME)
    wait_shown(child, { page = 1, img = WIDTH })
    eq(vim.uv.fs_stat(tmp .. "/pwned"), nil)
end

T["renders a page without starting a shell"] = function()
    open(child, "pages.pdf")
    eq(wait_shown(child, { page = 1, img = WIDTH }), { page = 1, img = WIDTH })
    eq(helpers.calls(child, "sh"), {})
end

T["merges page turns pressed during a render into one render"] = function()
    helpers.fake_env(child, { QUICKPDF_E2E_RENDER_DELAY = 1 })
    open(child, "pages.pdf")
    child.type_keys("n", "n", "n")
    eq(wait_shown(child, { page = 4, img = WIDTH }), { page = 4, img = WIDTH })
    eq(rendered_pages(child), { "1", "4" })
end

T["renders into a cache of its own, removed on exit"] = function()
    open(child, "pages.pdf")
    wait_shown(child, { page = 1, img = WIDTH })
    local instance_dir = vim.fs.dirname(helpers.config_paths(child)[1])
    eq(#vim.fs.find("page.png", { path = instance_dir }), 1)
    leave(child)
    eq(vim.uv.fs_stat(instance_dir), nil)
end

T["shows different PDFs in two instances at the same time"] = function()
    start(other)
    open(child, "pages.pdf")
    open(other, "pages.pdf")
    other.type_keys("n", "n")
    eq(wait_shown(other, { page = 3, img = WIDTH }), { page = 3, img = WIDTH })
    eq(shown(child), { page = 1, img = WIDTH })
end

T["keeps the other instance's viewer running when one quits"] = function()
    start(other)
    open(child, "pages.pdf")
    open(other, "pages.pdf")
    wait_shown(other, { page = 1, img = WIDTH })
    leave(child)
    eq(shown(other), { page = 1, img = WIDTH })
end

return T
