local project_setup = vim.fn.getcwd() .. "/.nvim/post-setup.lua"
if vim.fn.filereadable(project_setup) == 1 then
  dofile(project_setup)
end
