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

local function refresh_diagnostics_for_comment(comment)
  refresh_diagnostics_for_buf(comment.bufnr, comment.file)
  refresh_diagnostics_for_file(comment.file)
end

function M.setup(opts)
  M._config = config_mod.merge(opts)
  ui.set_config(M._config)
  vim.diagnostic.config({
    signs = {
      text = {
        [vim.diagnostic.severity.INFO] = M._config.ui.signs.info or "📝",
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
      if vim.api.nvim_win_is_valid(origin_win) then
        vim.api.nvim_set_current_win(origin_win)
      end
      if comment.file and comment.file ~= "" then
        vim.cmd("edit " .. vim.fn.fnameescape(comment.file))
      elseif comment.bufnr and vim.api.nvim_buf_is_valid(comment.bufnr) then
        vim.api.nvim_set_current_buf(comment.bufnr)
      else
        notify("Comment has no file or buffer", vim.log.levels.WARN)
        return
      end
      vim.api.nvim_win_set_cursor(0, { comment.range.start_line, 0 })
      refresh_diagnostics_for_comment(comment)
      ui.open_comment_prompt(comment, {
        initial_text = comment.text,
        on_submit = function(text)
          state.update(id, { text = text, timestamp = now() })
          refresh_diagnostics_for_comment(comment)
          notify(string.format("Updated comment #%d", id))
        end,
      })
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
      if vim.api.nvim_win_is_valid(origin_win) then
        vim.api.nvim_set_current_win(origin_win)
      end
      if comment.file and comment.file ~= "" then
        vim.cmd("edit " .. vim.fn.fnameescape(comment.file))
      elseif comment.bufnr and vim.api.nvim_buf_is_valid(comment.bufnr) then
        vim.api.nvim_set_current_buf(comment.bufnr)
      else
        notify("Comment has no file or buffer", vim.log.levels.WARN)
        return
      end
      vim.api.nvim_win_set_cursor(0, { comment.range.start_line, 0 })
      refresh_diagnostics_for_comment(comment)
      ui.open_comment_prompt(comment, {
        initial_text = comment.text,
        on_submit = function(text)
          state.update(id, { text = text, timestamp = now() })
          refresh_diagnostics_for_comment(comment)
          notify(string.format("Updated comment #%d", id))
        end,
      })
    end,
    on_show = function(id)
      local comment = state.get(id)
      if not comment then
        return
      end
      if vim.api.nvim_win_is_valid(origin_win) then
        vim.api.nvim_set_current_win(origin_win)
      end
      if comment.file and comment.file ~= "" then
        vim.cmd("edit " .. vim.fn.fnameescape(comment.file))
      elseif comment.bufnr and vim.api.nvim_buf_is_valid(comment.bufnr) then
        vim.api.nvim_set_current_buf(comment.bufnr)
      else
        notify("Comment has no file or buffer", vim.log.levels.WARN)
        return
      end
      vim.api.nvim_win_set_cursor(0, { comment.range.start_line, 0 })
      refresh_diagnostics_for_comment(comment)
      vim.diagnostic.open_float(0, {
        scope = "line",
        focus = false,
        source = "review.nvim",
        header = string.format("%s %s", M._config.ui.diagnostic_icon or "", M._config.ui.diagnostic_header or "Comment"),
      })
    end,
  })
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
