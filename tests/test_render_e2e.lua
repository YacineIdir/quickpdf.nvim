-- End-to-end rendering: the real plugin drives the real Quickshell daemon
-- (headless, QT_QPA_PLATFORM=offscreen) and the real pdftoppm. Only hyprctl
-- stays fake. Recording wrappers for `sh` and `pdftoppm` sit first on PATH.
-- Skipped when quickshell or poppler-utils is not installed.

local MiniTest = require("mini.test")
local helpers = dofile("tests/helpers.lua")

local child = MiniTest.new_child_neovim()
local eq = MiniTest.expect.equality

local ROOT = vim.fn.getcwd()
local FAKES_DIR = ROOT .. "/tests/fakes"
local PAGES_PDF = ROOT .. "/tests/fixtures/pages.pdf"
-- Render cache hard-coded in shell.qml.
local CACHE_PAGE = "/tmp/quickshell-pdf-cache/page.png"
-- Terminal width reported by the fake hyprctl, so the expected image width.
-- Unusual on purpose, so a page left by another viewer cannot match it.
local WIDTH = 613
-- Quotes, spaces and a command substitution: the shell would have run it.
local HOSTILE_NAME = [[l'examen "final" $(touch $QUICKPDF_PWNED) v'2.pdf]]

-- Dossier propre au cas : copie de la config, wrappers, XDG_RUNTIME_DIR,
-- journal d'appels.
local tmp

-- Écrit un script exécutable `name` dans `<tmp>/bin`.
local function write_script(name, lines)
    local path = tmp .. "/bin/" .. name
    vim.fn.writefile(vim.list_extend({ "#!/usr/bin/env bash" }, lines), path)
    vim.uv.fs_chmod(path, tonumber("755", 8))
end

-- Envoie un appel IPC au démon lancé par ce cas. Quickshell ne trouve une
-- instance que sur le même affichage : environnement vidé, sans
-- WAYLAND_DISPLAY ni DISPLAY, comme le démon.
local function ipc(...)
    local cmd = vim.list_extend({ "quickshell", "ipc", "-p", tmp .. "/qs", "call", "pdf" }, { ... })
    local env = { PATH = vim.env.PATH, HOME = vim.env.HOME, XDG_RUNTIME_DIR = tmp .. "/run" }
    return vim.system(cmd, { env = env, clear_env = true, text = true }):wait()
end

-- Page affichée par le visualiseur et largeur de l'image chargée.
local function shown()
    local page, img = (ipc("info").stdout or ""):match("page=(%d+) target=%d+ img=(%d+)")
    return { page = tonumber(page), img = tonumber(img) }
end

-- Attend jusqu'à 5 s que le visualiseur affiche `expected`, puis renvoie ce
-- qu'il affiche.
local function wait_shown(expected)
    vim.wait(5000, function()
        return vim.deep_equal(shown(), expected)
    end, 100)
    return shown()
end

-- Copie le PDF de test sous `name` et l'ouvre dans le Neovim enfant.
-- Renvoie son chemin absolu.
local function open(name)
    local path = tmp .. "/work/" .. name
    assert(vim.uv.fs_copyfile(PAGES_PDF, path))
    child.lua([[vim.cmd.edit(vim.fn.fnameescape(...))]], { path })
    return path
end

-- Pages demandées à pdftoppm, dans l'ordre des rendus.
local function rendered_pages()
    return vim.tbl_map(function(argv)
        for i, arg in ipairs(argv) do
            if arg == "-f" then
                return argv[i + 1]
            end
        end
    end, helpers.calls(child, "pdftoppm"))
end

local function setup()
    for _, program in ipairs({ "quickshell", "pdftoppm", "pdfinfo" }) do
        if vim.fn.executable(program) == 0 then
            MiniTest.skip(program .. " is not installed")
        end
    end

    tmp = vim.fn.tempname()
    for _, dir in ipairs({ "bin", "qs", "run", "work" }) do
        vim.fn.mkdir(tmp .. "/" .. dir, "p", tonumber("700", 8))
    end
    -- A copy of the config, so stray cleanup (pgrep on the config path) never
    -- touches a viewer the developer is running from this checkout.
    assert(vim.uv.fs_copyfile(ROOT .. "/quickshell/pdf_viewer/shell.qml", tmp .. "/qs/shell.qml"))
    local record = { "source " .. vim.fn.shellescape(FAKES_DIR .. "/_record.sh"), 'quickpdf_record "$@"' }
    write_script("hyprctl", { "exec " .. vim.fn.shellescape(FAKES_DIR .. "/hyprctl") .. ' "$@"' })
    write_script("sh", vim.list_extend(vim.deepcopy(record), { "exec " .. vim.fn.exepath("sh") .. ' "$@"' }))
    write_script(
        "pdftoppm",
        vim.list_extend(vim.deepcopy(record), {
            'sleep "${QUICKPDF_E2E_RENDER_DELAY:-0}"',
            "exec " .. vim.fn.exepath("pdftoppm") .. ' "$@"',
        })
    )
    -- A page left by an earlier render must not pass for this one.
    vim.fn.delete(CACHE_PAGE)

    child.restart({ "--noplugin", "-u", "tests/minit.lua" })
    child.lua(
        [[
        local tmp, width = ...
        vim.env.PATH = tmp .. "/bin:" .. vim.env.PATH
        vim.env.QUICKPDF_CALL_LOG = tmp .. "/calls.log"
        vim.env.QUICKPDF_PWNED = tmp .. "/pwned"
        vim.env.QUICKPDF_FAKE_TERM_WIDTH = tostring(width)
        vim.env.XDG_RUNTIME_DIR = tmp .. "/run"
        vim.env.QT_QPA_PLATFORM = "offscreen"
        vim.env.WAYLAND_DISPLAY = nil
        vim.env.DISPLAY = nil
        vim.env.HYPRLAND_INSTANCE_SIGNATURE = nil
        vim.fn.chdir(tmp .. "/work")
        require("quickpdf").setup({ qs_config = tmp .. "/qs" })
        ]],
        { tmp, WIDTH }
    )
end

local function teardown()
    if tmp then
        -- The daemon outlives the child Neovim; stop the one this case started.
        ipc("quit")
        vim.fn.delete(tmp, "rf")
        tmp = nil
    end
end

local T = MiniTest.new_set({
    hooks = {
        pre_case = setup,
        post_case = teardown,
        post_once = child.stop,
    },
})

T["renders a PDF whose name has quotes, spaces and $(...)"] = function()
    local path = open(HOSTILE_NAME)
    eq(wait_shown({ page = 1, img = WIDTH }), { page = 1, img = WIDTH })
    eq(vim.tbl_contains(helpers.calls(child, "pdftoppm")[1], path), true)
end

T["never runs a command written in the file name"] = function()
    open(HOSTILE_NAME)
    wait_shown({ page = 1, img = WIDTH })
    eq(vim.uv.fs_stat(tmp .. "/pwned"), nil)
end

T["renders a page without starting a shell"] = function()
    open("pages.pdf")
    eq(wait_shown({ page = 1, img = WIDTH }), { page = 1, img = WIDTH })
    eq(helpers.calls(child, "sh"), {})
end

T["merges page turns pressed during a render into one render"] = function()
    helpers.fake_env(child, { QUICKPDF_E2E_RENDER_DELAY = 1 })
    open("pages.pdf")
    child.type_keys("n", "n", "n")
    eq(wait_shown({ page = 4, img = WIDTH }), { page = 4, img = WIDTH })
    eq(rendered_pages(), { "1", "4" })
end

return T
