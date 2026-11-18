-- Shared test helpers: a child Neovim whose PATH starts with the fake
-- executables, and a reader for the calls they record
-- (docs/adr/0004-fake-executables-instead-of-injection.md).

local MiniTest = require("mini.test")

local H = {}

local FAKES_DIR = vim.fn.getcwd() .. "/tests/fakes"

-- Crée un Neovim enfant dont `setup()` repart d'un état propre : plugin
-- chargeable, faux exécutables en tête du PATH, journal d'appels vide.
function H.new_child_neovim()
    local child = MiniTest.new_child_neovim()

    child.setup = function()
        child.restart({ "--noplugin", "-u", "tests/minit.lua" })
        child.lua(
            [[
            local fakes, log = ...
            vim.env.QUICKPDF_CALL_LOG = log
            vim.env.PATH = fakes .. ":" .. vim.env.PATH
            ]],
            { FAKES_DIR, vim.fn.tempname() }
        )
    end

    return child
end

-- Déclare dans le Neovim enfant les variables d'environnement qui pilotent la
-- sortie des faux exécutables.
function H.fake_env(child, vars)
    child.lua(
        [[
        for name, value in pairs(...) do
            vim.env[name] = tostring(value)
        end
        ]],
        { vars }
    )
end

-- Liste les appels enregistrés pour `program`, du plus ancien au plus récent.
-- Chaque appel est la liste exacte de ses arguments, nom du programme inclus.
function H.calls(child, program)
    local log = child.lua_get([[vim.env.QUICKPDF_CALL_LOG]])
    local calls = {}
    if vim.fn.filereadable(log) == 0 then
        return calls
    end
    for _, line in ipairs(vim.fn.readfile(log)) do
        local fields = vim.split(line, " ", { trimempty = true })
        if fields[1] == program then
            local argv = { fields[1] }
            for i = 2, #fields do
                table.insert(argv, vim.base64.decode(fields[i]))
            end
            table.insert(calls, argv)
        end
    end
    return calls
end

-- Liste les chemins de config passés à `-p`, un par appel à quickshell.
function H.config_paths(child)
    local paths = {}
    for _, call in ipairs(H.calls(child, "quickshell")) do
        for i, arg in ipairs(call) do
            if arg == "-p" then
                table.insert(paths, call[i + 1])
            end
        end
    end
    return paths
end

return H
