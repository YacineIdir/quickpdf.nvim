-- A case that always fails, used to check the exit code of the test command.
-- Lives outside the collected `tests/test_*.lua` set, so only an explicit
-- `TESTS=` run picks it up.

local MiniTest = require("mini.test")

local T = MiniTest.new_set()

T["fails on purpose"] = function()
    MiniTest.expect.equality(1, 2)
end

return T
