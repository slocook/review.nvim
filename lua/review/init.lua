local config_mod = require("review.config")
local state = require("review.state")
local selection = require("review.selection")
local ui = require("review.ui")
local exporter = require("review.export")
local beads = require("review.beads")

local M = { _config = nil }
local diag_ns = vim.api.nvim_create_namespace("review.nvim")

local function ensure_config()
  if not M._config then
    M.setup()
  end
  return M._config
end

local function now()
  return os.date("%Y-%m-%d %H:%M:%S")
end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO)
end

local refresh_diagnostics_for_comment

local function get_codediff_explorer()
  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  if not ok then
    return nil
  end
  return lifecycle.get_explorer(vim.api.nvim_get_current_tabpage())
end

local function normalize_path(path)
  if not path or path == "" then
    return nil
  end
  return vim.fs.normalize(path)
end

local function relpath_from_root(path, root)
  path = normalize_path(path)
  root = normalize_path(root)
  if not path or not root then
    return nil
  end
  if path:sub(1, #root) == root then
    local rel = path:sub(#root + 1)
    rel = rel:gsub("^/", "")
    return rel
  end
  return nil
end

local function find_in_status(status_result, relpath)
  if not status_result or not relpath then
    return nil, nil
  end
  if status_result.conflicts then
    for _, file in ipairs(status_result.conflicts) do
      if file.path == relpath then
        return file, "conflicts"
      end
    end
  end
  for _, file in ipairs(status_result.unstaged or {}) do
    if file.path == relpath then
      return file, "unstaged"
    end
  end
  for _, file in ipairs(status_result.staged or {}) do
    if file.path == relpath then
      return file, "staged"
    end
  end
  return nil, nil
end

local function find_codediff_window_for_relpath(relpath)
  local ok, virtual_file = pcall(require, "codediff.core.virtual_file")
  if not ok then
    return nil
  end
  local tab = vim.api.nvim_get_current_tabpage()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    if name:match("^codediff://") then
      local _, _, filepath = virtual_file.parse_url(name)
      if filepath == relpath then
        return win
      end
    end
  end
  return nil
end

local function retry_jump_to_codediff(relpath, comment, origin_win, on_after, attempts_left)
  local win = find_codediff_window_for_relpath(relpath)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_cursor(0, { comment.range.start_line, 0 })
    refresh_diagnostics_for_comment(comment)
    if on_after then
      on_after()
    end
    return
  end
  if attempts_left <= 0 then
    if origin_win and vim.api.nvim_win_is_valid(origin_win) then
      vim.api.nvim_set_current_win(origin_win)
    end
    refresh_diagnostics_for_comment(comment)
    if on_after then
      on_after()
    end
    return
  end
  vim.defer_fn(function()
    retry_jump_to_codediff(relpath, comment, origin_win, on_after, attempts_left - 1)
  end, 80)
end

local function is_codediff_buf(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  return vim.api.nvim_buf_get_name(bufnr):match("^codediff://") ~= nil
end

local function codediff_tab_has_buffers()
  local tab = vim.api.nvim_get_current_tabpage()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if is_codediff_buf(buf) then
      return true
    end
  end
  return false
end

local function find_codediff_buf_for_path(path)
  if not path or path == "" then
    return nil, nil
  end
  local tab = vim.api.nvim_get_current_tabpage()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    if name:match("^codediff://") and name:find(path, 1, true) then
      return buf, win
    end
  end
  return nil, nil
end

local function jump_to_comment(comment, origin_win, on_after)
  local explorer = get_codediff_explorer()
  if explorer and explorer.git_root and comment.file and comment.file ~= "" then
    local relpath = relpath_from_root(comment.file, explorer.git_root)
    if relpath then
      local file_data, group = find_in_status(explorer.status_result, relpath)
      local selected = file_data and {
        path = file_data.path,
        old_path = file_data.old_path,
        status = file_data.status,
        git_root = explorer.git_root,
        group = group or explorer.current_file_group or "unstaged",
      } or {
        path = relpath,
        git_root = explorer.git_root,
        group = explorer.current_file_group or "unstaged",
      }
      explorer.on_file_select(selected)
      vim.defer_fn(function()
        retry_jump_to_codediff(relpath, comment, origin_win, on_after, 5)
      end, 80)
      return true
    end
  end

  local target_buf, target_win
  if comment.bufnr and vim.api.nvim_buf_is_valid(comment.bufnr) and is_codediff_buf(comment.bufnr) then
    target_buf = comment.bufnr
    local wins = vim.fn.win_findbuf(target_buf)
    if #wins > 0 then
      target_win = wins[1]
    end
  end

  if not target_buf and comment.file and comment.file ~= "" then
    target_buf, target_win = find_codediff_buf_for_path(comment.file)
  end

  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
  elseif origin_win and vim.api.nvim_win_is_valid(origin_win) then
    vim.api.nvim_set_current_win(origin_win)
  end

  if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
    vim.api.nvim_set_current_buf(target_buf)
  elseif comment.file and comment.file ~= "" then
    if codediff_tab_has_buffers() then
      notify("Comment file not in current CodeDiff view", vim.log.levels.WARN)
      return false
    end
    vim.cmd("edit " .. vim.fn.fnameescape(comment.file))
  elseif comment.bufnr and vim.api.nvim_buf_is_valid(comment.bufnr) then
    vim.api.nvim_set_current_buf(comment.bufnr)
  else
    notify("Comment has no file or buffer", vim.log.levels.WARN)
    return false
  end

  vim.api.nvim_win_set_cursor(0, { comment.range.start_line, 0 })
  refresh_diagnostics_for_comment(comment)
  if on_after then
    on_after()
  end
  return true
end

local function selection_for_opts(opts)
  local buf = vim.api.nvim_get_current_buf()
  if opts and opts.range and opts.range > 0 then
    return selection.capture_visual(buf)
  end
  return selection.capture_current_line(buf)
end

local function ensure_selection_file(sel)
  if sel.file and sel.file ~= "" then
    return true
  end
  notify("Unable to resolve file path for selection", vim.log.levels.WARN)
  return false
end

local function build_comment(selection_data, text)
  return {
    file = selection_data.file,
    buffer_name = selection_data.buffer_name,
    bufnr = selection_data.bufnr,
    side = selection_data.side,
    kind = selection_data.kind,
    filetype = selection_data.filetype,
    range = selection_data.range,
    code = selection_data.code,
    text = text,
    timestamp = now(),
  }
end

local function comment_to_diagnostic(comment)
  return {
    lnum = comment.range.start_line - 1,
    end_lnum = comment.range.end_line - 1,
    col = 0,
    end_col = 0,
    severity = vim.diagnostic.severity.INFO,
    source = "review.nvim",
    message = comment.text or "",
  }
end

local function refresh_diagnostics_for_file(file)
  if not file or file == "" then
    return
  end
  local bufnr = vim.fn.bufnr(file, false)
  if bufnr == -1 then
    return
  end
  local diags = {}
  for _, comment in ipairs(state.list()) do
    if comment.file == file then
      table.insert(diags, comment_to_diagnostic(comment))
    end
  end
  vim.diagnostic.set(diag_ns, bufnr, diags, {
    virtual_text = false,
    signs = true,
    underline = false,
  })
end

local function refresh_diagnostics_for_buf(bufnr, file_hint)
  if not bufnr or bufnr < 1 then
    return
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local diags = {}
  for _, comment in ipairs(state.list()) do
    if comment.bufnr == bufnr or (file_hint and comment.file == file_hint) then
      table.insert(diags, comment_to_diagnostic(comment))
    end
  end
  vim.diagnostic.set(diag_ns, bufnr, diags, {
    virtual_text = false,
    signs = true,
    underline = false,
  })
end

refresh_diagnostics_for_comment = function(comment)
  refresh_diagnostics_for_buf(comment.bufnr, comment.file)
  refresh_diagnostics_for_file(comment.file)
end

local function open_comment_float(cfg)
  local ui_cfg = cfg.ui or {}
  local border = ui_cfg.float_border or "rounded"
  local header = "💬 Comment"

  -- Get diagnostics for current line
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lnum = cursor[1] - 1
  local diags = vim.diagnostic.get(bufnr, { lnum = lnum, namespace = diag_ns })

  if #diags == 0 then
    return
  end

  -- Build content lines
  local lines = { header }
  for _, diag in ipairs(diags) do
    for line in vim.gsplit(diag.message, "\n", { plain = true }) do
      table.insert(lines, line)
    end
  end

  -- Calculate dimensions
  local max_width = 0
  for _, line in ipairs(lines) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
  end
  local width = math.min(max_width + 2, math.floor(vim.o.columns * 0.8))
  local height = #lines

  -- Create float buffer
  local float_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)
  vim.bo[float_buf].modifiable = false

  -- Highlight header
  vim.api.nvim_buf_add_highlight(float_buf, -1, "DiagnosticHeader", 0, 0, -1)

  -- Position: left-anchored or cursor-relative
  local win_opts = {
    relative = "win",
    anchor = "NW",
    width = width,
    height = height,
    style = "minimal",
    border = border,
    focusable = false,
  }

  if ui_cfg.float_anchor == "left" then
    -- Account for sign column, line numbers, fold column
    local textoff = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].textoff or 0
    win_opts.row = vim.fn.winline()
    win_opts.col = textoff
  else
    win_opts.row = vim.fn.winline()
    win_opts.col = cursor[2]
  end

  local win = vim.api.nvim_open_win(float_buf, false, win_opts)

  -- Auto-close on cursor move
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave" }, {
    buffer = bufnr,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })
end

function M.show_comment()
  local cfg = ensure_config()
  open_comment_float(cfg)
end

function M.setup(opts)
  M._config = config_mod.merge(opts)
  ui.set_config(M._config)
  vim.diagnostic.config({
    signs = {
      text = {
        [vim.diagnostic.severity.INFO] = "💬",
      },
    },
  }, diag_ns)
  vim.api.nvim_create_autocmd("BufEnter", {
    group = vim.api.nvim_create_augroup("ReviewDiagnostics", { clear = true }),
    callback = function(args)
      local name = vim.api.nvim_buf_get_name(args.buf)
      if name ~= "" then
        refresh_diagnostics_for_file(name)
      end
    end,
  })
  return M._config
end

function M.comment(opts)
  local cfg = ensure_config()
  local selection_data = selection_for_opts(opts)
  if not ensure_selection_file(selection_data) then
    return
  end

  ui.open_comment_prompt(selection_data, {
    on_submit = function(text)
      local comment = build_comment(selection_data, text)
      state.add(comment)
      refresh_diagnostics_for_comment(comment)
      notify(string.format("Added comment #%d", comment.id))
      if cfg.ui.auto_show_float then
        vim.schedule(function()
          open_comment_float(cfg)
        end)
      end
    end,
  })
end

function M.list_comments()
  ensure_config()
  local origin_win = vim.api.nvim_get_current_win()
  ui.open_comment_list(state.list(), {
    fetch_comments = state.list,
    origin_win = origin_win,
    on_jump = function(id)
      local comment = state.get(id)
      if not comment then
        return
      end
      if not jump_to_comment(comment, origin_win, function()
        ui.open_comment_prompt(comment, {
          initial_text = comment.text,
          on_submit = function(text)
            state.update(id, { text = text, timestamp = now() })
            refresh_diagnostics_for_comment(comment)
            notify(string.format("Updated comment #%d", id))
          end,
        })
      end) then
        return
      end
    end,
    on_delete = function(id)
      local comment = state.get(id)
      state.delete(id)
      if comment then
        refresh_diagnostics_for_comment(comment)
      end
      notify(string.format("Deleted comment #%d", id))
    end,
    on_edit = function(id)
      local comment = state.get(id)
      if not comment then
        return
      end
      if not jump_to_comment(comment, origin_win, function()
        ui.open_comment_prompt(comment, {
          initial_text = comment.text,
          on_submit = function(text)
            state.update(id, { text = text, timestamp = now() })
            refresh_diagnostics_for_comment(comment)
            notify(string.format("Updated comment #%d", id))
          end,
        })
      end) then
        return
      end
    end,
    on_show = function(id)
      local comment = state.get(id)
      if not comment then
        return
      end
      if not jump_to_comment(comment, origin_win, function()
        open_comment_float(M._config)
      end) then
        return
      end
    end,
  })
end

local function collect_candidates(bufnr, file)
  local items = {}
  for _, comment in ipairs(state.list()) do
    if (comment.bufnr and comment.bufnr == bufnr) or (file and comment.file == file) then
      table.insert(items, comment)
    end
  end
  table.sort(items, function(a, b)
    if a.range.start_line == b.range.start_line then
      return a.id < b.id
    end
    return a.range.start_line < b.range.start_line
  end)
  return items
end

local function current_context()
  local bufnr = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == "" then
    file = nil
  end
  return bufnr, file, vim.api.nvim_win_get_cursor(0)[1]
end

local function find_comment_at_line(comments, line)
  for _, comment in ipairs(comments) do
    if line >= comment.range.start_line and line <= comment.range.end_line then
      return comment
    end
  end
  return nil
end

function M.delete_comment_at_cursor()
  ensure_config()
  local bufnr, file, line = current_context()
  local candidates = collect_candidates(bufnr, file)
  local comment = find_comment_at_line(candidates, line)
  if not comment then
    notify("No comment on current line", vim.log.levels.WARN)
    return
  end
  state.delete(comment.id)
  refresh_diagnostics_for_comment(comment)
  notify(string.format("Deleted comment #%d", comment.id))
end

local function export_single(cfg, comments)
  local path = string.format("%s/review-%s.md", cfg.export.dir, state.session_id)
  local lines = exporter.render_all(comments)
  local ok, err = exporter.write_lines(path, lines)
  if not ok then
    return nil, err
  end
  return { path }
end

local function export_per_comment(cfg, comments)
  local paths = {}
  for _, comment in ipairs(comments) do
    local path = string.format("%s/comment-%s-%d.md", cfg.export.dir, state.session_id, comment.id)
    local lines = exporter.render_comment(comment)
    local ok, err = exporter.write_lines(path, lines)
    if not ok then
      return nil, err
    end
    table.insert(paths, path)
  end
  return paths
end

function M.export_markdown()
  local cfg = ensure_config()
  local comments = state.list()
  if #comments == 0 then
    notify("No comments to export", vim.log.levels.WARN)
    return
  end

  local paths, err
  if cfg.export.mode == "single" then
    paths, err = export_single(cfg, comments)
  else
    paths, err = export_per_comment(cfg, comments)
  end

  if not paths then
    notify(err or "Export failed", vim.log.levels.ERROR)
    return
  end

  notify(string.format("Exported %d markdown file(s)", #paths))
  return paths
end

local function resolve_parent_id(cfg)
  local cwd = vim.loop.cwd()
  local parent_id = beads.infer_parent_id(cfg.beads, cwd)
  if parent_id and parent_id ~= "" then
    return parent_id
  end
  if not cfg.beads.prompt_if_missing then
    return nil
  end
  local input = vim.fn.input("Parent bead id (blank for none): ")
  if input == "" then
    return nil
  end
  return input
end

local function ensure_body_file(path, lines)
  local ok, err = exporter.write_lines(path, lines)
  if not ok then
    return nil, err
  end
  return path
end

function M.create_beads()
  local cfg = ensure_config()
  if not cfg.beads.enabled then
    notify("Beads integration disabled", vim.log.levels.WARN)
    return
  end

  local comments = state.list()
  if #comments == 0 then
    notify("No comments to create beads for", vim.log.levels.WARN)
    return
  end

  local parent_id = resolve_parent_id(cfg)
  local cwd = vim.loop.cwd()

  if cfg.beads.prompt_if_missing and (not parent_id or parent_id == "") then
    notify("No parent bead specified; creating top-level bead(s)")
  end

  if cfg.export.mode == "single" then
    local path = string.format("%s/review-%s.md", cfg.export.dir, state.session_id)
    local lines = exporter.render_all(comments)
    local body_file, err = ensure_body_file(path, lines)
    if not body_file then
      notify(err or "Failed to prepare bead body", vim.log.levels.ERROR)
      return
    end

    local title = "Code review"
    local id, create_err = beads.create_bead(cfg.beads, {
      title = title,
      parent_id = parent_id,
      body_file = body_file,
      cwd = cwd,
    })
    if not id then
      notify(create_err or "Failed to create bead", vim.log.levels.ERROR)
      return
    end
    notify("Created review bead " .. id)
    return id
  end

  local created = 0
  for _, comment in ipairs(comments) do
    local path = string.format("%s/comment-%s-%d.md", cfg.export.dir, state.session_id, comment.id)
    local lines = exporter.render_comment(comment)
    local body_file, err = ensure_body_file(path, lines)
    if not body_file then
      notify(err or "Failed to prepare bead body", vim.log.levels.ERROR)
      return
    end
    local title = string.format("Review comment %d", comment.id)
    local id, create_err = beads.create_bead(cfg.beads, {
      title = title,
      parent_id = parent_id,
      body_file = body_file,
      cwd = cwd,
    })
    if not id then
      notify(create_err or "Failed to create bead", vim.log.levels.ERROR)
      return
    end
    created = created + 1
  end
  notify(string.format("Created %d comment beads", created))
end

function M.export()
  local cfg = ensure_config()
  if cfg.beads.enabled then
    return M.create_beads()
  end
  return M.export_markdown()
end

return M
