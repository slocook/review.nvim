local M = {}

local function system(cmd, opts)
  local result = vim.system(cmd, opts):wait()
  result.stdout = result.stdout or ""
  result.stderr = result.stderr or ""
  return result
end

local function parse_id(output)
  local ok, decoded = pcall(vim.json.decode, output)
  if ok and decoded and decoded.id then
    return tostring(decoded.id)
  end
  local id = output:match("Created issue:%s*([%w%-%_/]+)")
  if id then
    return id
  end
  id = output:match("Created:%s*([%w%-%_/]+)")
  if id then
    return id
  end
  return nil
end

local function is_parent_error(stderr)
  if not stderr or stderr == "" then
    return false
  end
  return stderr:lower():match("parent") ~= nil and stderr:lower():match("required") ~= nil
end

function M.get_repo_root(cwd)
  local res = system({ "git", "rev-parse", "--show-toplevel" }, { text = true, cwd = cwd })
  if res.code ~= 0 then
    return cwd
  end
  return vim.trim(res.stdout)
end

function M.infer_parent_id(cfg, cwd)
  if not cfg.parent_from_branch then
    return nil
  end
  local res = system({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, { text = true, cwd = cwd })
  if res.code ~= 0 then
    return nil
  end
  local branch = vim.trim(res.stdout)
  local match = branch:match(cfg.branch_pattern)
  return match
end

local function build_create_args(cfg, title, parent_id, body_file)
  local args = { cfg.cmd, "create", title }
  if parent_id and parent_id ~= "" then
    table.insert(args, "--parent")
    table.insert(args, parent_id)
  end
  if cfg.body_mode == "body-file" and body_file then
    table.insert(args, "--body-file")
    table.insert(args, body_file)
  end
  for _, arg in ipairs(cfg.extra_args or {}) do
    table.insert(args, arg)
  end
  return args
end

function M.create_bead(cfg, opts)
  local root = M.get_repo_root(opts.cwd)
  local args = build_create_args(cfg, opts.title, opts.parent_id, opts.body_file)
  local res = system(args, { text = true, cwd = root })
  if res.code ~= 0 and not opts.parent_id and is_parent_error(res.stderr) then
    local retry_args = build_create_args(cfg, opts.title, nil, opts.body_file)
    res = system(retry_args, { text = true, cwd = root })
  end
  if res.code ~= 0 and cfg.body_mode == "body-file" and opts.body_file then
    local retry_args = build_create_args(vim.tbl_extend("force", cfg, { body_mode = "none" }), opts.title, opts.parent_id, nil)
    res = system(retry_args, { text = true, cwd = root })
  end
  if res.code ~= 0 then
    return nil, res.stderr ~= "" and res.stderr or res.stdout
  end
  local id = parse_id(res.stdout)
  if id then
    return id
  end
  return "created"
end

return M
