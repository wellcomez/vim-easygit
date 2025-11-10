-- easygit.lua - Git helper functions for Neovim
-- Converted from autoload/easygit.vim to Lua

local M = {}

-- Extract git directory by path
-- if suspend is given as an argument, no error message
function M.gitdir(path, suspend)
  local suspend = suspend or false
  local resolved_path = vim.fn.resolve(vim.fn.fnamemodify(path, ":p"))
  local gitdir = M._find_gitdir(resolved_path)
  if vim.fn.empty(gitdir) == 1 and not suspend then
    vim.api.nvim_echo({{"Git directory not found", "ErrorMsg"}}, false, {})
  end
  return gitdir
end

function M._find_gitdir(path)
  if not vim.fn.empty(vim.env.GIT_DIR) then
    return vim.env.GIT_DIR
  end
  if vim.g.easygit_enable_root_rev_parse ~= 0 then
    local old_cwd = vim.fn.getcwd()
    local cwd = vim.fn.fnamemodify(path, ":p:h")
    vim.cmd("silent lcd " .. vim.fn.fnameescape(cwd))
    local root = vim.fn.system("git rev-parse --show-toplevel")
    vim.cmd("silent lcd " .. vim.fn.fnameescape(old_cwd))
    if vim.v.shell_error ~= 0 then
      return ""
    end
    return vim.fn.substitute(root, "\\r\\?\\n", "", "g") .. "/.git"
  else
    local dir = vim.fn.finddir(".git", vim.fn.expand(path) .. ";")
    if vim.fn.empty(dir) == 1 then
      return ""
    end
    return vim.fn.fnamemodify(dir, ":p:h")
  end
end

-- If cwd inside current file git root, return cwd, otherwise return git root
function M.smart_root(suspend)
  local suspend = suspend or false
  local gitdir = M.gitdir(vim.fn.expand("%"), suspend)
  if vim.fn.empty(gitdir) == 1 then
    return ""
  end
  local root = vim.fn.fnamemodify(gitdir, ":h")
  local cwd = vim.fn.getcwd()
  if string.find(cwd, "^" .. vim.fn.escape(root, "[]$^~*.\\?")) then
    return cwd
  else
    return root
  end
end

-- cd or lcd to base directory of current file's git root
function M.cd(is_local)
  local dir = M.gitdir(vim.fn.expand("%"))
  if vim.fn.empty(dir) == 1 then
    return
  end
  local cmd = is_local and "lcd" or "cd"
  vim.cmd(cmd .. " " .. vim.fn.fnamemodify(dir, ":h"))
end

-- `cmd` string for git checkout
-- Checkout current file if cmd empty
function M.checkout(cmd)
  local root = M.smart_root()
  if vim.fn.empty(root) == 1 then
    return
  end
  local old_cwd = vim.fn.getcwd()
  local view = vim.fn.winsaveview()
  vim.cmd("silent lcd " .. vim.fn.fnameescape(root))
  local command
  if string.len(cmd) > 0 then
    command = "git checkout " .. cmd
  else
    -- relative path
    local file = vim.fn.substitute(vim.fn.expand("%:p"), root .. "/", "", "")
    command = "git checkout -- " .. file
  end
  local output = vim.fn.system(command)
  if vim.v.shell_error ~= 0 and output ~= "" then
    vim.api.nvim_echo({{output, "WarningMsg"}}, false, {})
  else
    vim.api.nvim_echo({{"done", "None"}}, false, {})
  end
  vim.cmd("silent lcd " .. vim.fn.fnameescape(old_cwd))
  vim.cmd("silent edit")
end

-- show the commit ref with option.edit and option.all
-- Using gitdir of current file
-- fold the file if option.fold is true
-- option.file could contain the file for show
-- option.fold if 0, not fold
-- option.all show all files change
-- option.gitdir could contain gitdir to work on
function M.show(args, option)
  local fold = option.fold or 1
  local gitdir = option.gitdir or ""
  if vim.fn.empty(gitdir) == 1 then
    gitdir = M.gitdir(vim.fn.expand("%"))
  end
  if vim.fn.empty(gitdir) == 1 then
    return
  end
  local showall = option.all or 0
  local format = "--pretty=format:'" .. M._escape("commit %H%nparent %P%nauthor %an <%ae> %ad%ncommitter %cn <%ce> %cd%n %e%n%n%s%n%n%b") .. "' "
  local command
  if showall == 1 then
    command = "git --no-pager"
      .. " --git-dir=" .. gitdir
      .. " show  --no-color " .. format .. args
  else
    local root = vim.fn.fnamemodify(gitdir, ":h")
    local file = option.file or
      vim.fn.substitute(vim.fn.expand("%:p"), root .. "/", "", "")
    command = "git --no-pager"
      .. " --git-dir=" .. gitdir
      .. " show --no-color " .. format .. args .. " -- " .. file
  end
  local opt = vim.deepcopy(option)
  opt.title = "__easygit__show__" .. M._find_object(args)
        .. (showall == 1 and "" or "/" .. vim.fn.fnamemodify(file, ":r"))
        .. "__"
  local res = M._execute(command, opt)
  if res == -1 then
    return
  end
  if fold == 1 then
    vim.opt_local.foldenable = true
  end
  vim.opt_local.filetype = "git"
  vim.opt_local.foldtext = "v:lua.require('easygit').foldtext()"
  vim.opt_local.foldmethod = "syntax"
  vim.b.gitdir = gitdir
  vim.fn.setpos(".", {vim.fn.bufnr("%"), 7, 0, 0})
  vim.keymap.set("n", "u", M.show_parent_commit, { buffer = true, silent = true })
  vim.keymap.set("n", "d", M.show_next_commit, { buffer = true, silent = true })
end

function M.show_parent_commit()
  local line2 = vim.fn.getline(2)
  local commit = vim.fn.matchstr(line2, "\\v\\s\\zs.+\\$")
  if vim.fn.empty(commit) == 1 then
    return
  end
  M.show(commit, {
    edit = "edit",
    gitdir = vim.b.gitdir,
    all = 1,
  })
end

function M.show_next_commit()
  local line1 = vim.fn.getline(1)
  local commit = vim.fn.matchstr(line1, "\\v\\s\\zs.+\\$")
  local commit_new = M._next_commit(commit, vim.b.gitdir)
  if vim.fn.empty(commit_new) == 1 then
    return
  end
  M.show(commit_new, {
    edit = "edit",
    gitdir = vim.b.gitdir,
    all = 1,
  })
end

function M._sub(str, pat, rep)
  return vim.fn.substitute(str, "\\v\\C" .. pat, rep, "")
end

function M._find_object(args)
  if string.len(args) == 0 then
    return "head"
  end
  local arr = vim.fn.split(args, "\\v\\s+")
  for _, str in ipairs(arr) do
    if not string.match(str, "\\v^-") then
      return str
    end
  end
  return ""
end

function M.foldtext()
  if vim.o.foldmethod ~= "syntax" then
    return vim.fn.foldtext()
  elseif string.match(vim.fn.getline(vim.v.foldstart), "^diff ") then
    local add, remove = -1, -1
    local filename = ""
    for lnum = vim.v.foldstart, vim.v.foldend do
      if filename == "" and string.match(vim.fn.getline(lnum), "^[+-]\\{3\\} [abciow12]/") then
        filename = string.sub(vim.fn.getline(lnum), 7, -1)
      end
      if string.match(vim.fn.getline(lnum), "^+") then
        add = add + 1
      elseif string.match(vim.fn.getline(lnum), "^-") then
        remove = remove + 1
      elseif string.match(vim.fn.getline(lnum), "^Binary ") then
        local binary = 1
      end
    end
    if filename == "" then
      filename = vim.fn.matchstr(vim.fn.getline(vim.v.foldstart), "^diff .\\{-\\} a/\\zs.*\\ze b/")
    end
    if filename == "" then
      filename = string.sub(vim.fn.getline(vim.v.foldstart), 6, -1)
    end
    if vim.g["binary"] then
      return "Binary: " .. filename
    else
      return (add < 10 and remove < 100 and " " or "") .. add .. "+ " .. (remove < 10 and add < 100 and " " or "") .. remove .. "- " .. filename
    end
  elseif string.match(vim.fn.getline(vim.v.foldstart), "^# .*:$") then
    local lines = {}
    for i = vim.v.foldstart, vim.v.foldend do
      table.insert(lines, vim.fn.getline(i))
    end
    local filtered_lines = {}
    for _, line in ipairs(lines) do
      if string.match(line, "^#\\t") then
        table.insert(filtered_lines, line)
      end
    end
    for i, line in ipairs(filtered_lines) do
      filtered_lines[i] = M._sub(line, "^#\\t%%(fixed: +|add: +)=", "")
    end
    for i, line in ipairs(filtered_lines) do
      filtered_lines[i] = M._sub(line, "^([[:alpha:] ]+): +(.*)", "%2 (%1)")
    end
    return vim.fn.getline(vim.v.foldstart) .. " " .. table.concat(filtered_lines, ", ")
  end
  return vim.fn.foldtext()
end

-- diff current file with ref in vertical split buffer
function M.diff_this(ref, edit)
  local gitdir = M.gitdir(vim.fn.expand("%"))
  if vim.fn.empty(gitdir) == 1 then
    return
  end
  local ref_val = string.len(ref) > 0 and ref or "head"
  local edit_cmd = edit or "vsplit"
  local ft = vim.bo.filetype
  local bnr = vim.fn.bufnr("%")
  local root = vim.fn.fnamemodify(gitdir, ":h")
  local file = vim.fn.substitute(vim.fn.expand("%:p"), root .. "/", "", "")
  local command = "git --no-pager --git-dir=" .. gitdir
      .. " show --no-color "
      .. ref_val .. ":" .. file
  local option = {
    edit = edit_cmd,
    title = "__easygit__file__" .. ref_val .. "_" .. vim.fn.fnamemodify(file, ":t")
  }
  vim.cmd("diffthis")
  local res = M._execute(command, option)
  if res == -1 then
    vim.cmd("diffoff")
    return
  end
  vim.bo.filetype = ft
  vim.cmd("diffthis")
  vim.b.gitdir = gitdir
  vim.opt_local.foldenable = true
  vim.fn.setwinvar(0, "easygit_diff_origin", bnr)
  vim.fn.setpos(".", {vim.fn.bufnr("%"), 0, 0, 0})
end

-- Show diff window with optional command args or `git diff`
function M.diff_show(args, edit)
  edit = edit or "edit"
  local root = M.smart_root()
  if vim.fn.empty(root) == 1 then
    return
  end
  local old_cwd = vim.fn.getcwd()
  vim.cmd("silent lcd " .. vim.fn.fnameescape(root))
  local command = "git --no-pager diff --no-color " .. args
  local options = {
    edit = edit,
    title = "__easygit__diff__" .. M._find_object(args),
  }
  local res = M._execute(command, options)
  vim.cmd("silent lcd " .. vim.fn.fnameescape(old_cwd))
  if res == -1 then
    return
  end
  vim.opt_local.filetype = "git"
  vim.opt_local.foldmethod = "syntax"
  vim.opt_local.foldlevel = 99
  vim.opt_local.foldtext = "v:lua.require('easygit').foldtext()"
  vim.fn.setpos(".", {vim.fn.bufnr("%"), 0, 0, 0})
end

-- Show diff content in preview window
function M.diff_preview(args)
  local root = M.smart_root()
  if vim.fn.empty(root) == 1 then
    return
  end
  local old_cwd = vim.fn.getcwd()
  vim.cmd("silent lcd " .. vim.fn.fnameescape(root))
  local command = "git --no-pager diff --no-color " .. args
  local temp = vim.fn.fnamemodify(vim.fn.tempname(), ":h") .. "/" .. vim.fn.fnamemodify(M._find_object(args), ":t")
  local cmd = ":silent !git --no-pager diff --no-color " .. args .. " > " .. temp .. " 2>&1"
  vim.cmd(cmd)
  vim.cmd("silent lcd " .. vim.fn.fnameescape(old_cwd))
  vim.cmd("silent pedit! " .. vim.fn.fnameescape(temp))
  vim.cmd("wincmd P")
  vim.opt_local.filetype = "git"
  vim.opt_local.foldmethod = "syntax"
  vim.opt_local.foldlevel = 99
  vim.opt_local.foldtext = "v:lua.require('easygit').foldtext()"
end

-- Commit current file with message
function M.commit_current(args)
  if string.len(args) == 0 then
    vim.api.nvim_echo({{"Msg should not empty", "ErrorMsg"}}, false, {})
    return
  end
  local root = M.smart_root()
  if vim.fn.empty(root) == 1 then
    return
  end
  local old_cwd = vim.fn.getcwd()
  vim.cmd("silent lcd " .. vim.fn.fnameescape(root))
  local file = vim.fn.bufname("%")
  local command = "git commit " .. file .. " -m " .. vim.fn.shellescape(args)
  local output = vim.fn.system(command)
  if vim.v.shell_error ~= 0 and output ~= "" then
    vim.api.nvim_echo({{output, "ErrorMsg"}}, false, {})
  else
    vim.api.nvim_echo({{"done", "None"}}, false, {})
    vim.cmd("silent w")
  end
  vim.cmd("silent lcd " .. vim.fn.fnameescape(old_cwd))
end

-- blame current file
function M.blame(edit)
  edit = edit or "edit"
  local root = M.smart_root()
  if vim.fn.empty(root) == 1 then
    return
  end
  local cwd = vim.fn.getcwd()
  -- source bufnr
  local bnr = vim.fn.bufnr("%")
  vim.cmd("lcd " .. vim.fn.fnameescape(root))
  local view = vim.fn.winsaveview()
  local cmd = "git --no-pager blame -- " .. vim.fn.expand("%")
  local opt = {
    edit = edit,
    title = "__easygit__blame__",
  }
  local res = M._execute(cmd, opt)
  if res == -1 then
    return
  end
  vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
  vim.bo.filetype = "easygitblame"
  vim.fn.winrestview(view)
  M._blame_highlight()
  vim.keymap.set("n", "d", function() M._diff_from_blame(bnr) end, { buffer = true, silent = true })
  vim.keymap.set("n", "p", function() M._show_ref_from_blame(bnr) end, { buffer = true, silent = true })
end

function M._diff_from_blame(bnr)
  local line = vim.fn.getline(".")
  local commit = vim.fn.matchstr(line, "^\\^\\=\\zs\\x\\+")
  local wnr = vim.fn.bufwinnr(bnr)
  if wnr == -1 then
    vim.cmd("silent b " .. bnr)
  else
    vim.cmd(wnr .. "wincmd w")
  end
  M.diff_this(commit)
  if wnr == -1 then
    vim.b.blame_bufnr = bnr
  end
end

function M._show_ref_from_blame(bnr)
  local line = vim.fn.getline(".")
  local commit = vim.fn.matchstr(line, "^\\^\\=\\zs\\x\\+")
  local gitdir = M.gitdir(vim.fn.bufname(bnr))
  if vim.fn.empty(gitdir) == 1 then
    return
  end
  local root = vim.fn.fnamemodify(gitdir, ":h")
  local option = {
    edit = "split",
    gitdir = gitdir,
    all = 1,
  }
  M.show(commit, option)
end

local hash_colors = {}

function M._blame_highlight()
  vim.b.current_syntax = "fugitiveblame"
  local conceal = vim.fn.has("conceal") == 1 and " conceal" or ""
  local arg = vim.b.fugitive_blame_arguments or ""
  vim.cmd("syn match EasygitblameBoundary \"^\\^\"")
  vim.cmd("syn match EasygitblameBlank \"^\\s\\+\\s\\@=\" nextgroup=EasygitblameAnnotation,fugitiveblameOriginalFile,EasygitblameOriginalLineNumber skipwhite")
  vim.cmd("syn match EasygitblameHash \"\\%(^\\^\\=\\)\\@<=\\x\\{7,40\\}\\>\" nextgroup=EasygitblameAnnotation,EasygitblameOriginalLineNumber,fugitiveblameOriginalFile skipwhite")
  vim.cmd("syn match EasygitblameUncommitted \"\\%(^\\^\\=\\)\\@<=0\\{7,40\\}\\>\" nextgroup=EasygitblameAnnotation,EasygitblameOriginalLineNumber,fugitiveblameOriginalFile skipwhite")
  vim.cmd("syn region EasygitblameAnnotation matchgroup=EasygitblameDelimiter start=\"(\" end=\"\\%( \\d\\+\\)\\@<=)\" contained keepend oneline")
  vim.cmd("syn match EasygitblameTime \"[0-9:/+-][0-9:/+ -]*[0-9:/+-]\\%( \\+\\d\\+)\\)\\@=\" contained containedin=EasygitblameAnnotation")
  vim.cmd("exec 'syn match EasygitblameLineNumber \" *\\d\\+)\\@=\" contained containedin=EasygitblameAnnotation'..conceal")
  vim.cmd("exec 'syn match EasygitblameOriginalFile \" \\%(\\f\\+\\D\\@<=\\|\\D\\@=\\f\\+\\)\\%\\(\\%(\\s\\+\\d\\+\\)\\=\\s\\%((\\|\\s*\\d\\+)\\)\\)\\@=\" contained nextgroup=EasygitblameOriginalLineNumber,EasygitblameAnnotation skipwhite'..(string.find(arg, 'f') and '' or conceal)")
  vim.cmd("exec 'syn match EasygitblameOriginalLineNumber \" *\\d\\+\\%\\(\\s(\\)\\@=\" contained nextgroup=EasygitblameAnnotation skipwhite'..(string.find(arg, 'n') and '' or conceal)")
  vim.cmd("exec 'syn match EasygitblameOriginalLineNumber \" *\\d\\+\\%\\(\\s\\+\\d\\+)\\)\\@=\" contained nextgroup=EasygitblameShort skipwhite'..(string.find(arg, 'n') and '' or conceal)")
  vim.cmd("syn match EasygitblameShort \" \\d\\+)\" contained contains=EasygitblameLineNumber")
  vim.cmd("syn match EasygitblameNotCommittedYet \"(\\@<=Not Committed Yet\\>\" contained containedin=EasygitblameAnnotation")
  vim.cmd("hi def link EasygitblameBoundary Keyword")
  vim.cmd("hi def link EasygitblameHash Identifier")
  vim.cmd("hi def link EasygitblameUncommitted Ignore")
  vim.cmd("hi def link EasygitblameTime PreProc")
  vim.cmd("hi def link EasygitblameLineNumber Number")
  vim.cmd("hi def link EasygitblameOriginalFile String")
  vim.cmd("hi def link EasygitblameOriginalLineNumber Float")
  vim.cmd("hi def link EasygitblameShort EasygitblameDelimiter")
  vim.cmd("hi def link EasygitblameDelimiter Delimiter")
  vim.cmd("hi def link EasygitblameNotCommittedYet Comment")
  local seen = {}
  for lnum = 1, vim.fn.line("$") do
    local hash = vim.fn.matchstr(vim.fn.getline(lnum), "^\\^\\=\\zs\\x\\{6\\}")
    if hash ~= "" and hash ~= "000000" and not seen[hash] then
      seen[hash] = 1
      hash_colors[hash] = ""
      vim.cmd("exe 'syn match EasygitblameHash" .. hash .. " \"\\%(^\\^\\=\\)\\@<=" .. hash .. "\\x\\{1,34\\}\\>\" nextgroup=EasygitblameAnnotation,EasygitblameOriginalLineNumber,fugitiveblameOriginalFile skipwhite'")
    end
  end
  M._rehighlight_blame()
end

function M._rehighlight_blame()
  for hash, cterm in pairs(hash_colors) do
    if cterm ~= "" or vim.fn.has("gui_running") == 1 then
      vim.cmd("hi EasygitblameHash" .. hash .. " guifg=#" .. hash .. hash_colors[hash])
    else
      vim.cmd("hi link EasygitblameHash" .. hash .. " Identifier")
    end
  end
end

-- Open commit buffer and commit changes on save
function M.commit(args, gitdir, root)
  local gitdir = gitdir or M.gitdir(vim.fn.expand("%"))
  if vim.fn.empty(gitdir) == 1 then
    return
  end
  local msgfile = gitdir .. "/COMMIT_EDITMSG"
  local root = root or M.smart_root()
  local old_cwd = vim.fn.getcwd()
  vim.cmd("lcd " .. vim.fn.fnameescape(root))
  local cmd = "git commit " .. args
  if vim.fn.has("gui_running") == 1 or vim.fn.has("nvim") == 1 then
    local out = vim.fn.tempname()
    vim.cmd("noautocmd silent !env GIT_EDITOR=false " .. cmd .. " 1>/dev/null 2> " .. out)
    vim.cmd("lcd " .. vim.fn.fnameescape(old_cwd))
    local errors = vim.fn.readfile(out)
    -- bufleave
    if gitdir then
      if vim.fn.empty(errors) == 0 then
        vim.cmd("redraw")
        vim.api.nvim_echo({{table.concat(errors, "\\n"), "ErrorMsg"}}, false, {})
      end
      -- Wait for git to complete
      if pcall(require, "timer") then
        local timer = require("timer")
        timer.start(100, M._commit_callback)
      end
      return
    end
    local error = errors[#errors - 1] or errors[#errors] or "!"
    if error == "!" then M._message("nothing to commit, working directory clean"); return end
    -- should contain false
    if not string.find(error, "false'?%.?$") then
      return
    end
    os.remove(out)
    local h = vim.api.nvim_win_get_height(0) - 5
    vim.cmd("silent keepalt " .. h .. "split " .. vim.fn.fnameescape(msgfile))
    local args_new = args
    args_new = vim.fn.substitute(args_new, "%(%(^| )-- )@<!%(^| )@<=%(-[esp]|--edit|--interactive|--patch|--signoff)%($| )", "", "g")
    args_new = vim.fn.substitute(args_new, [[%(%(^| )-- )@<!%(^| )@<=%(-c|--reedit-message|--reuse-message|-F|--file|-m|--message)%(%s+|%=)%(''[^'']*''|"[^"]*"|\.|\S)*]], "", "g")
    args_new = vim.fn.substitute(args_new, "%(%^| )@<=[%#]%(\\:\\w)*", function(m) return vim.fn.expand(m[0]) end, "g")
    args_new = vim.fn.substitute(args_new, "\\ze -- |$", " --no-edit --no-interactive --no-signoff", "")
    args_new = "-F tmp " .. args_new
    if not string.find(args_new, "%(%^| \\)--cleanup%>") then
      args_new = "--cleanup=strip " .. args_new
    end
    vim.b.easygit_commit_root = root
    vim.b.easygit_commit_arguments = args_new
    vim.bo.bufhidden = "wipe"
    vim.bo.filetype = "gitcommit"
    vim.opt_local.foldenable = false
    return "1"
  else
    vim.cmd("noautocmd !" .. cmd)
    vim.cmd("lcd " .. vim.fn.fnameescape(old_cwd))
  end
end

function M._commit_callback(timer_id)
  if vim.b.git_branch then
    vim.b.git_branch = nil
  end
  vim.cmd("redraws!")
end

function M.move(force, source, destination)
  if source == destination then
    return
  end
  local root = M.smart_root()
  if vim.fn.empty(root) == 1 then
    return
  end
  local old_cwd = vim.fn.getcwd()
  vim.cmd("lcd " .. vim.fn.fnameescape(root))
  local source = vim.fn.empty(source) == 1 and vim.fn.bufname("%") or source
  local command = "git mv " .. (force and "-f " or "") .. source .. " " .. destination
  local output = vim.fn.system(command)
  if vim.v.shell_error ~= 0 and output ~= "" then
    vim.cmd("lcd " .. vim.fn.fnameescape(old_cwd))
    vim.api.nvim_echo({{output, "ErrorMsg"}}, false, {})
    return
  end
  local dest = vim.fn.substitute(destination, "\\v^\\./", "", "")
  if source == vim.fn.bufname("%") then
    local tail = vim.fn.fnamemodify(vim.fn.bufname("%"), ":t")
    if dest == "." then
      vim.cmd("keepalt edit! " .. vim.fn.fnameescape(tail))
    elseif vim.fn.isdirectory(dest) == 1 then
      vim.cmd("keepalt edit! " .. vim.fn.fnameescape(vim.fn.simplify(dest .. "/" .. tail)))
    else
      -- file name change
      vim.cmd("keepalt saveas! " .. vim.fn.fnameescape(dest))
    end
    vim.cmd("silent! bdelete " .. vim.fn.bufnr(source))
  end
  vim.cmd("lcd " .. vim.fn.fnameescape(old_cwd))
end

function M.remove(force, args, current)
  local root = M.smart_root()
  if vim.fn.empty(root) == 1 then
    return
  end
  local old_cwd = vim.fn.getcwd()
  vim.cmd("lcd " .. vim.fn.fnameescape(root))
  local list = vim.fn.split(args, "\\v[^\\\\]\\zs\\s")
  local files = {}
  for _, val in ipairs(list) do
    if not string.match(val, "^-") then
      table.insert(files, vim.fn.substitute(val, "^\\\\./", "", ""))
    end
  end
  local force = force and not string.find(args, "\\v<-f>") and "-f " or ""
  local cname = vim.fn.substitute(vim.fn.expand("%"), " ", "\\\\ ", "g")
  if current then
    table.insert(files, cname)
  end
  local command = "git rm " .. force .. args
  command = command .. (current and cname or "")
  local output = vim.fn.system(command)
  if vim.v.shell_error ~= 0 and output ~= "" then
    vim.api.nvim_echo({{output, "ErrorMsg"}}, false, {})
    vim.cmd("lcd " .. vim.fn.fnameescape(old_cwd))
    return
  end
  for _, name in ipairs(files) do
    if name == cname then
      if vim.fn.exists(":Bdelete") == 2 then
        vim.cmd("Bdelete " .. name)
      else
        local alt = vim.fn.bufname("#")
        if vim.fn.empty(alt) == 0 then
          vim.cmd("e " .. alt)
        end
        vim.cmd("silent bdelete " .. name)
      end
    else
      vim.cmd("silent! bdelete " .. name)
    end
  end
  vim.cmd("lcd " .. vim.fn.fnameescape(old_cwd))
end

function M.complete(file, branch, tag)
  local root = M.smart_root()
  local output = ""
  local cwd = vim.fn.getcwd()
  vim.cmd("lcd " .. vim.fn.fnameescape(root))
  if file == 1 then
    output = output .. M._system("git ls-tree --name-only -r HEAD")
  end
  if branch == 1 then
    output = output .. M._system("git branch --no-color -a | cut -c3- | sed 's:^remotes\\/::'")
  end
  if tag == 1 then
    output = output .. M._system("git tag")
  end
  vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
  return output
end

function M.complete_checkout()
  local root = M.smart_root()
  local output = ""
  local cwd = vim.fn.getcwd()
  vim.cmd("lcd " .. vim.fn.fnameescape(root))
  output = output .. M._system("git branch --no-color | cut -c3-")
  output = output .. M._system("git ls-files -m --exclude-standard")
  vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
  return output
end

function M.complete_add()
  local root = M.smart_root()
  local cwd = vim.fn.getcwd()
  vim.cmd("lcd " .. vim.fn.fnameescape(root))
  local output = M._system("git ls-files -m -d -o --exclude-standard")
  vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
  return output
end

function M.complete_commit(arg_lead, cmd_line, cursor_pos)
  local opts = {"--message", "--fixup", "--amend", "--cleanup", "--status", "--only", "-signoff"}
  if string.match(arg_lead, "\\v^-") then
    local filtered_opts = {}
    for _, opt in ipairs(opts) do
      if string.find(opt, "^" .. arg_lead) == 1 then
        table.insert(filtered_opts, opt)
      end
    end
    return filtered_opts
  end
  local root = M.smart_root()
  local cwd = vim.fn.getcwd()
  vim.cmd("lcd " .. vim.fn.fnameescape(root))
  local output = M._system("git status -s|cut -c 4-")
  vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
  if vim.fn.empty(output) == 0 then
    local files = vim.fn.split(output, "\\n")
    local filtered_files = {}
    for _, file in ipairs(files) do
      if string.find(file, "^" .. arg_lead) == 1 then
        table.insert(filtered_files, file)
      end
    end
    return filtered_files
  end
  return {}
end

function M.complete_reset(arg_lead)
  local opts = {"--soft", "--hard", "--merge", "--keep", "--mixed"}
  if string.match(arg_lead, "\\v^-") then
    local filtered_opts = {}
    for _, opt in ipairs(opts) do
      if string.find(opt, "^" .. arg_lead) == 1 then
        table.insert(filtered_opts, opt)
      end
    end
    return filtered_opts
  end
  local root = M.smart_root()
  local cwd = vim.fn.getcwd()
  vim.cmd("lcd " .. vim.fn.fnameescape(root))
  local output = M._system("git diff --staged --name-status | cut -f 2")
  vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
  if vim.fn.empty(output) == 0 then
    local files = vim.fn.split(output, "\\n")
    local filtered_files = {}
    for _, file in ipairs(files) do
      if string.find(file, "^" .. arg_lead) == 1 then
        table.insert(filtered_files, file)
      end
    end
    return filtered_files
  end
  return {}
end

function M.complete_revert(arg_lead)
  local opts = {"--continue", "--quit", "--abort"}
  if string.match(arg_lead, "\\v^-") then
    local filtered_opts = {}
    for _, opt in ipairs(opts) do
      if string.find(opt, "^" .. arg_lead) == 1 then
        table.insert(filtered_opts, opt)
      end
    end
    return filtered_opts
  end
  return {}
end

function M.list_remotes()
  local root = M.smart_root()
  if vim.fn.empty(root) == 1 then
    return ""
  end
  local cwd = vim.fn.getcwd()
  vim.cmd("lcd " .. vim.fn.fnameescape(root))
  local output = M._system("git branch -r | sed 's:/.*::'|uniq")
  vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
  return vim.fn.substitute(output, "\\v(^|\\n)\\zs\\s*", "", "g")
end

function M.revert(args)
  local root = M.smart_root()
  if vim.fn.empty(root) == 1 then
    return
  end
  local cwd = vim.fn.getcwd()
  vim.cmd("lcd " .. vim.fn.fnameescape(root))
  M._system("git revert " .. args)
  vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
end

function M.reset(args)
  local root = M.smart_root()
  if vim.fn.empty(root) == 1 then
    return
  end
  local cwd = vim.fn.getcwd()
  vim.cmd("lcd " .. vim.fn.fnameescape(root))
  M._system("git reset " .. args)
  vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
end

-- Run git add with files in smartRoot
function M.add(...)
  local files = {...}
  local root = M.smart_root()
  if vim.fn.empty(root) == 1 then
    return
  end
  local cwd = vim.fn.getcwd()
  vim.cmd("lcd " .. vim.fn.fnameescape(root))
  local args
  if #files == 0 then
    args = vim.fn.expand("%")
  else
    args = table.concat(vim.tbl_map(function(x) return vim.fn.shellescape(x) end, files), " ")
  end
  local command = "git add " .. args
  M._system(command)
  M._reset_gutter(vim.fn.bufnr("%"))
  vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
end

-- Open git status buffer from smart root
function M.status()
  local root = M.smart_root()
  if vim.fn.empty(root) == 1 then
    return
  end
  local cwd = vim.fn.getcwd()
  vim.cmd("lcd " .. vim.fn.fnameescape(root))
  M._execute("git --no-pager status --long -b", {
    edit = "edit",
    title = "__easygit_status__",
  })
  vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
end

function M.read(args)
  local root = M.smart_root()
  if vim.fn.empty(root) == 1 then
    return
  end
  local old_cwd = vim.fn.getcwd()
  vim.cmd("lcd " .. vim.fn.fnameescape(root))
  local path = args or vim.fn.expand("%")
  if vim.fn.empty(path) == 1 then
    return
  end
  local output = vim.fn.system("git --no-pager show :" .. path)
  if vim.v.shell_error ~= 0 and output ~= "" then
    vim.api.nvim_echo({{output, "ErrorMsg"}}, false, {})
    return -1
  end
  local save_cursor = vim.fn.getcurpos()
  vim.cmd("edit " .. path)
  vim.cmd("%d")
  local eol = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 and "\\v\\n" or "\\v\\r?\\n"
  local list = vim.fn.split(output, eol)
  if #list > 0 then
    vim.fn.setline(1, list[1])
    for i = 2, #list do
      vim.fn.append(i-1, list[i])
    end
  end
  vim.fn.setpos(".", save_cursor)
  M._reset_gutter(vim.fn.bufnr(path))
  vim.cmd("lcd " .. vim.fn.fnameescape(old_cwd))
end

function M.merge(args)
  if vim.fn.argc() == 0 then
    return
  end
  local root = M.smart_root()
  if vim.fn.empty(root) == 1 then
    return
  end
  local cwd = vim.fn.getcwd()
  vim.cmd("lcd " .. vim.fn.fnameescape(root))
  local command = "git merge " .. args
  M._system(command)
  vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
end

function M.grep(args)
  local root = M.smart_root()
  if vim.fn.empty(root) == 1 then
    return
  end
  local cwd = vim.fn.getcwd()
  vim.cmd("lcd " .. vim.fn.fnameescape(root))
  local old_grepprg = vim.o.grepprg
  local old_grepformat = vim.o.grepformat
  vim.o.grepprg = "git --no-pager grep --no-color -n $*"
  vim.o.grepformat = "%f:%l:%m"
  vim.cmd("silent grep " .. args)
  if vim.g.easygit_grep_open ~= 0 then
    vim.cmd("cwindow")
  end
  vim.o.grepprg = old_grepprg
  vim.o.grepformat = old_grepformat
end

-- Execute command and show the result by options
-- option.edit edit command used for open result buffer
-- option.pipe pipe current buffer to command
-- option.title required title for the new tmp buffer
-- option.nokeep if 1, not keepalt
function M._execute(cmd, option)
  local edit = option.edit or "edit"
  local pipe = option.pipe or 0
  local bnr = vim.fn.bufnr("%")
  if edit == "pedit" then
    edit = "new +setlocal\\ previewwindow"
  end
  if not string.find(edit, "keepalt") and not option.nokeep then
    edit = "keepalt " .. edit
  end
  local output
  if pipe == 1 then
    local stdin = table.concat(vim.fn.getline(1, "$"), "\n")
    output = vim.fn.system(cmd, stdin)
  else
    output = vim.fn.system(cmd)
  end
  if vim.v.shell_error ~= 0 and output ~= "" then
    vim.api.nvim_echo({{output, "ErrorMsg"}}, false, {})
    return -1
  end
  vim.cmd(edit .. " " .. option.title)
  vim.b.easygit_edit_cmd = option.edit or "edit"  -- Store the original edit command
  vim.keymap.set("n", "q", M._smart_quit, { buffer = true, silent = true })
  vim.b.easygit_prebufnr = bnr
  local eol = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 and "\\v\\n" or "\\v\\r?\\n"
  local list = vim.fn.split(output, eol)
  if #list > 0 then
    vim.fn.setline(1, list[1])
    for i = 2, #list do
      vim.fn.append(i-1, list[i])
    end
  end
  vim.bo.buftype = "nofile"
  vim.bo.readonly = true
  vim.bo.bufhidden = "wipe"
end

function M._system(command)
  local output = vim.fn.system(command)
  if vim.v.shell_error ~= 0 and output ~= "" then
    vim.api.nvim_echo({{output, "ErrorMsg"}}, false, {})
    return ""
  end
  return output
end

function M._next_commit(commit, gitdir)
  local output = vim.fn.system("git --git-dir=" .. gitdir
        .. " log --reverse --ancestry-path "
        .. commit .. "..master | head -n 1 | cut -d \\  -f 2")
  if vim.v.shell_error ~= 0 and output ~= "" then
    vim.api.nvim_echo({{output, "ErrorMsg"}}, false, {})
    return
  end
  return vim.fn.substitute(output, "\\n", "", "")
end

function M._smart_quit()
  local bnr = vim.b.blame_bufnr or ""
  local edit = vim.b.easygit_edit_cmd or "edit"  -- Store original edit command
  if string.find(edit, "edit") then
    local success, _ = pcall(vim.cmd, "b " .. vim.b.easygit_prebufnr)
    if not success then
      vim.cmd("q")
    end
  else
    vim.cmd("q")
  end
  if bnr ~= "" then
    M.blame()
  end
end

function M._message(msg)
  vim.api.nvim_echo({{msg, "MoreMsg"}}, false, {})
end

function M.dispatch(name, args)
  local root = M.smart_root()
  if vim.fn.empty(root) == 1 then
    return
  end
  local cwd = vim.fn.getcwd()
  local cmd = "git " .. name .. " " .. args
  if vim.fn.has("gui_running") == 0 then
    local pre = vim.fn.exists(":Nrun") == 2 and "Nrun " or "!"
    if vim.fn.has("nvim") == 1 and pre == "!" then
      pre = ":terminal "
    end
    vim.cmd("lcd " .. vim.fn.fnameescape(root))
    vim.cmd(pre .. cmd)
    vim.keymap.set("n", "q", function() vim.cmd("bd!") end, { buffer = true, silent = true })
    vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
  else
    local title = "easygit-" .. name
    if vim.fn.exists(":Start") == 2 then
      vim.cmd("Start! -title=" .. title .. " -dir=" .. root .. " " .. cmd)
    elseif vim.fn.exists(":ItermStartTab") == 2 then
      vim.cmd("ItermStartTab! -title=" .. title .. " -dir=" .. root .. " " .. cmd)
    else
      vim.cmd("!" .. cmd)
    end
  end
end

function M._winshell()
  return string.find(vim.o.shell, "cmd") or (vim.o.shellslash ~= nil and not vim.o.shellslash)
end

function M._escape(str)
  if M._winshell() then
    local cmd_escape_char = vim.o.shellxquote == "(" and "^" or "^^^"
    return vim.fn.substitute(str, "\\v\\C[<>]", cmd_escape_char, "g")
  end
  return str
end

function M._reset_gutter(bufnr)
  if vim.fn.exists("*gitgutter#process_buffer") == 2 then
    vim.fn["gitgutter#process_buffer"](bufnr, 1)
  end
end

return M