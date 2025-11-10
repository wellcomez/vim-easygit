-- Plugin file for easygit in Lua
-- Converted from plugin/easygit.vim to Lua

local easygit = require("easygit")

-- Check if already loaded or if vim version is too old
if vim.g.did_easygit_loaded or vim.fn.has("nvim") == 0 and vim.v.version < 700 then
  return
end

vim.g.did_easygit_loaded = 1

-- Autocmd to handle commit buffer when leaving
local group = vim.api.nvim_create_augroup("easygit", { clear = true })

vim.api.nvim_create_autocmd({ "VimLeavePre", "BufDelete" }, {
  pattern = "COMMIT_EDITMSG",
  callback = function()
    if vim.fn.has("gui_running") == 0 and vim.fn.has("nvim") == 0 then
      return
    end
    local args = vim.b.easygit_commit_arguments or ""
    if args ~= "" then
      vim.b.easygit_commit_arguments = ""
      local gitdir = vim.fn.fnamemodify(vim.fn.bufname(0), ":p:h")
      -- cat current file content to tmpfile
      local out = vim.fn.tempname()
      vim.fn.system("cat " .. vim.fn.fnameescape(vim.fn.bufname(0)) .. " > " .. out)
      args = vim.fn.substitute(args, "\\v\\s-F\\stmp", " -F " .. out, "")
      local root = vim.b.easygit_commit_root
      return easygit.commit(args, gitdir, root)
    end
  end,
  group = group,
})

-- Restore diff status if no diff buffer open
vim.api.nvim_create_autocmd("BufWinLeave", {
  pattern = "__easygit__file*",
  callback = function()
    local wnr = vim.fn.bufwinnr(vim.fn.expand("<abuf>"))
    local val = vim.fn.getwinvar(wnr, "easygit_diff_origin")
    if vim.fn.len(val) == 0 then
      return
    end
    for i = 1, vim.fn.winnr("$") do
      if i == wnr then
        goto continue
      end
      if vim.fn.len(vim.fn.getwinvar(i, "easygit_diff_origin")) > 0 then
        return
      end
      ::continue::
    end
    local wnr = vim.fn.bufwinnr(val)
    if wnr > 0 then
      vim.cmd(wnr .. "wincmd w")
      vim.cmd("diffoff")
    end
  end,
  group = group,
})

-- Helper functions for commands
local function edit(args)
  local option = {
    all = 1,
    edit = vim.g.easygit_edit_edit_command or "edit",
    fold = vim.g.easygit_edit_fold or 1,
  }
  easygit.show(args, option)
end

local function diff_show(args)
  local edit = vim.g.easygit_diff_edit_command or "edit"
  easygit.diff_show(args, edit)
end

local function move(bang, source, destination)
  if vim.fn.argc() ~= 3 then
    vim.api.nvim_echo({{"Gmove requires source and destination", "ErrorMsg"}}, false, {})
    return
  end
  local force = (bang == "!") and 1 or 0
  easygit.move(force, source, destination)
end

local function rename(bang, destination)
  local force = (bang == "!") and 1 or 0
  easygit.move(force, "", destination)
end

local function diff_this(arg)
  local ref = (arg and #arg > 0) and arg or "head"
  local edit = vim.g.easygit_diff_this_edit or "vsplit"
  easygit.diff_this(ref, edit)
end

local function remove(bang, ...)
  local files = {...}
  local force = (bang == "!") and 1 or 0
  -- keep the \ for space
  local list = {}
  for _, val in ipairs(files) do
    table.insert(list, vim.fn.substitute(val, " ", "\\\\ ", ""))
  end
  local filtered_files = {}
  for _, val in ipairs(list) do
    if not string.match(val, "^-") then
      table.insert(filtered_files, val)
    end
  end
  local current = #filtered_files == 0
  local files_str = table.concat(list, " ")
  easygit.remove(force, files_str, current)
end

local function git_files(arg, line, pos)
  return easygit.complete(1, 0, 0)
end

local function try_git_cd(cmd_type)
  if vim.fn.empty(vim.bo.buftype) == 0 then
    return
  end
  if string.match(vim.fn.expand("%"), "^%w+://") then
    return
  end
  if vim.o.previewwindow then
    return
  end
  local gitdir = easygit.gitdir(vim.fn.expand("%"), 1)
  if vim.fn.empty(gitdir) == 1 then
    if vim.w.original_cwd and string.find(vim.fn.expand("%:p"), vim.w.original_cwd) == 1 then
      vim.cmd(cmd_type .. " " .. vim.w.original_cwd)
    end
    return
  end
  local root = vim.fn.fnamemodify(gitdir, ":h")
  local cwd = vim.fn.getcwd()
  if string.find(cwd, root) ~= 1 then
    vim.w.original_cwd = cwd
    vim.cmd(cmd_type .. " " .. root)
  end
end

-- Completion functions
local function complete_checkout(arg, line, pos)
  return easygit.complete_checkout()
end

local function complete_branch(arg, line, pos)
  return easygit.complete(0, 1, 0)
end

local function complete_show(arg, line, pos)
  return easygit.complete(0, 1, 0)
end

local function complete_diff_this(arg, line, pos)
  return easygit.complete(1, 1, 0)
end

local function commit_current(args)
  if args == "" then
    local root = easygit.smart_root()
    if vim.fn.empty(root) == 1 then
      return
    end
    local file = vim.fn.substitute(vim.fn.expand("%:p"), root .. "/", "", "")
    easygit.commit(" -v -- " .. file)
  else
    easygit.commit_current(args)
  end
end

-- Define commands if enabled
if vim.g.easygit_enable_command ~= 0 then
  vim.api.nvim_create_user_command("Gcd", function() easygit.cd(false) end, { nargs = 0 })
  vim.api.nvim_create_user_command("Glcd", function() easygit.cd(true) end, { nargs = 0 })
  vim.api.nvim_create_user_command("Gblame", function() easygit.blame() end, { nargs = 0 })
  vim.api.nvim_create_user_command("Gstatus", function() easygit.status() end, { nargs = 0 })
  vim.api.nvim_create_user_command("GcommitCurrent", function(opts) commit_current(opts.args) end, { nargs = "*" })
  vim.api.nvim_create_user_command("GdiffThis", function(opts) diff_this(opts.args) end, { 
    nargs = "?", 
    complete = complete_diff_this 
  })
  vim.api.nvim_create_user_command("Ggrep", function(opts) easygit.grep(opts.args) end, { 
    nargs = "+", 
    complete = git_files 
  })
  vim.api.nvim_create_user_command("Gedit", function(opts) edit(opts.args) end, { 
    nargs = "*", 
    complete = complete_show 
  })
  vim.api.nvim_create_user_command("Gdiff", function(opts) diff_show(opts.args) end, { 
    nargs = "*", 
    complete = complete_branch 
  })
  vim.api.nvim_create_user_command("Gremove", function(opts) 
    remove(opts.bang, unpack(opts.fargs)) 
  end, { 
    nargs = "*", 
    bang = true,
    complete = git_files 
  })
  vim.api.nvim_create_user_command("Grename", function(opts) 
    rename(opts.bang, opts.fargs[1])
  end, { 
    nargs = 1, 
    bang = true,
    complete = git_files 
  })
  vim.api.nvim_create_user_command("Gmove", function(opts) 
    move(opts.bang, opts.fargs[1], opts.fargs[2])
  end, { 
    nargs = "+", 
    bang = true,
    complete = git_files 
  })
  vim.api.nvim_create_user_command("Gcheckout", function(opts) easygit.checkout(opts.args) end, { 
    nargs = "*", 
    complete = complete_checkout 
  })
  vim.api.nvim_create_user_command("Gpush", function(opts) 
    easygit.dispatch("push", opts.args)
  end, { 
    nargs = "*", 
    complete = easygit.list_remotes 
  })
  vim.api.nvim_create_user_command("Gfetch", function(opts) 
    easygit.dispatch("fetch", opts.args)
  end, { 
    nargs = "*", 
    complete = easygit.list_remotes 
  })
  vim.api.nvim_create_user_command("Gpull", function(opts) 
    easygit.dispatch("pull", opts.args)
  end, { 
    nargs = "*", 
    complete = easygit.list_remotes 
  })
  vim.api.nvim_create_user_command("Gadd", function(opts) 
    easygit.add(unpack(opts.fargs))
  end, { 
    nargs = "*", 
    complete = easygit.complete_add 
  })
  vim.api.nvim_create_user_command("Gmerge", function(opts) 
    easygit.merge(opts.args)
  end, { 
    nargs = "+", 
    complete = complete_branch 
  })
  vim.api.nvim_create_user_command("Gread", function(opts) 
    easygit.read(opts.args)
  end, { 
    nargs = "?", 
    complete = easygit.complete_add 
  })
  vim.api.nvim_create_user_command("Grevert", function(opts) 
    easygit.revert(opts.args)
  end, { 
    nargs = "+", 
    complete = easygit.complete_revert 
  })
  vim.api.nvim_create_user_command("Greset", function(opts) 
    easygit.reset(opts.args)
  end, { 
    nargs = "+", 
    complete = easygit.complete_reset 
  })
  vim.api.nvim_create_user_command("Gcommit", function(opts) 
    easygit.commit(opts.args)
  end, { 
    nargs = "+", 
    complete = easygit.complete_commit 
  })
end

-- Auto lcd/tcd functionality
local auto_group = vim.api.nvim_create_augroup("easygit_auto_lcd", { clear = true })

if vim.g.easygit_auto_lcd ~= 0 then
  vim.api.nvim_create_autocmd({ "BufWinEnter", "BufReadPost" }, {
    pattern = "*",
    callback = function() try_git_cd("lcd") end,
    group = auto_group,
  })
elseif vim.g.easygit_auto_tcd ~= 0 and vim.fn.exists(":tcd") == 2 then
  vim.api.nvim_create_autocmd({ "BufWinEnter", "BufReadPost" }, {
    pattern = "*",
    callback = function() try_git_cd("tcd") end,
    group = auto_group,
  })
end