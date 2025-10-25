require("kaleb.set")
require("kaleb.remap")
require("kaleb.commands")
require("kaleb.lazy")
local project_setup = vim.fn.getcwd() .. "/.nvim/setup.lua"
if vim.fn.filereadable(project_setup) == 1 then
  dofile(project_setup)
end
