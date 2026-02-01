local M = { config = nil }

local function trim_empty_tail(lines)
  local last = #lines
  while last > 0 and lines[last] == "" do
    lines[last] = nil
    last = last - 1
  end
  return lines
end

local function build_preview_lines(selection)
  local lines = {}
  table.insert(lines, "File: " .. (selection.file or "(unknown)"))
  table.insert(lines, string.format("Lines: %d-%d (%s)", selection.range.start_line, selection.range.end_line, selection.side))
  table.insert(lines, "Kind: " .. selection.kind)
  table.insert(lines, "")
  for index, line in ipairs(selection.code or {}) do
    local lineno = selection.range.start_line + index - 1
    table.insert(lines, string.format("%4d | %s", lineno, line))
  end
  return lines
end

local function calc_layout(cfg)
  local width = math.floor(vim.o.columns * cfg.width)
  local height = math.floor(vim.o.lines * cfg.height)
  if width < 40 then
    width = math.min(40, vim.o.columns)
  end
  if height < 10 then
    height = math.min(10, vim.o.lines)
  end
  local row = math.floor((vim.o.lines - height) * 0.5 - 1)
  local col = math.floor((vim.o.columns - width) * 0.5)
  if row < 0 then
    row = 0
  end
  if col < 0 then
    col = 0
  end
  return width, height, row, col
end

local function open_window(buf, cfg, opts)
  return vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = opts.width,
    height = opts.height,
    row = opts.row,
    col = opts.col,
    border = cfg.border,
    title = opts.title,
    title_pos = "center",
    style = "minimal",
  })
end

function M.set_config(cfg)
  M.config = cfg
end

function M.open_comment_prompt(selection, opts)
  opts = opts or {}
  local cfg = M.config.ui

  local width, height, row, col = calc_layout(cfg)
  local preview_height = math.floor(height * cfg.preview_height)
  if preview_height < 3 then
    preview_height = 0
  end
  local input_height = height - preview_height

  local preview_win
  if preview_height > 0 then
    local preview_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, build_preview_lines(selection))
    vim.bo[preview_buf].modifiable = false
    vim.bo[preview_buf].bufhidden = "wipe"
    vim.bo[preview_buf].buftype = "nofile"

    preview_win = open_window(preview_buf, cfg, {
      width = width,
      height = preview_height,
      row = row,
      col = col,
      title = "Selection",
    })
  end

  local input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[input_buf].bufhidden = "wipe"
  vim.bo[input_buf].buftype = "nofile"
  vim.bo[input_buf].filetype = "markdown"

  local input_lines = {}
  if opts.initial_text and opts.initial_text ~= "" then
    input_lines = vim.split(opts.initial_text, "\n", { plain = true })
  end
  vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, input_lines)

  local input_row = row + preview_height
  local input_title = string.format("%s  [<C-s> save, q cancel]", cfg.title)
  local input_win = open_window(input_buf, cfg, {
    width = width,
    height = input_height,
    row = input_row,
    col = col,
    title = input_title,
  })

  local function close_all()
    if preview_win and vim.api.nvim_win_is_valid(preview_win) then
      vim.api.nvim_win_close(preview_win, true)
    end
    if vim.api.nvim_win_is_valid(input_win) then
      vim.api.nvim_win_close(input_win, true)
    end
  end

  local function submit()
    local lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
    trim_empty_tail(lines)
    local text = table.concat(lines, "\n")
    if text == "" then
      vim.notify("Review comment cannot be empty", vim.log.levels.WARN)
      return
    end
    close_all()
    if opts.on_submit then
      opts.on_submit(text)
    end
  end

  local function cancel()
    close_all()
    if opts.on_cancel then
      opts.on_cancel()
    end
  end

  vim.keymap.set({ "n", "i" }, cfg.keymaps.submit, submit, { buffer = input_buf, silent = true })
  vim.keymap.set("n", "<CR>", submit, { buffer = input_buf, silent = true })
  vim.keymap.set("n", cfg.keymaps.cancel, cancel, { buffer = input_buf, silent = true })

  vim.cmd("startinsert")
end

local function render_comment_list(buf, comments)
  local lines = {}
  local line_map = {}
  for index, comment in ipairs(comments) do
    local summary = (comment.text or ""):match("[^\n]*") or ""
    local file = comment.file or "(unknown)"
    local range = string.format("%d-%d", comment.range.start_line, comment.range.end_line)
    lines[#lines + 1] = string.format("#%d %s:%s %s", comment.id, file, range, summary)
    line_map[index] = comment.id
  end
  if #comments == 0 then
    lines = { "(no comments)" }
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.b[buf].review_comment_line_map = line_map
end

function M.open_comment_list(comments, opts)
  opts = opts or {}
  local cfg = M.config.ui
  local width, height, row, col = calc_layout(cfg)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "reviewlist"
  render_comment_list(buf, comments)

  local win = open_window(buf, cfg, {
    width = width,
    height = height,
    row = row,
    col = col,
    title = "Review Comments",
  })

  local function refresh()
    local latest = opts.fetch_comments and opts.fetch_comments() or comments
    render_comment_list(buf, latest)
  end

  local function get_selected_id()
    local line = vim.api.nvim_win_get_cursor(win)[1]
    return vim.b[buf].review_comment_line_map and vim.b[buf].review_comment_line_map[line]
  end

  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true })

  vim.keymap.set("n", "<CR>", function()
    local id = get_selected_id()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if id and opts.on_jump then
      opts.on_jump(id)
    end
  end, { buffer = buf, silent = true })

  vim.keymap.set("n", "p", function()
    local id = get_selected_id()
    if id and opts.on_show then
      opts.on_show(id)
    end
  end, { buffer = buf, silent = true })

  vim.keymap.set("n", "d", function()
    local id = get_selected_id()
    if id and opts.on_delete then
      opts.on_delete(id)
      refresh()
    end
  end, { buffer = buf, silent = true })

  vim.keymap.set("n", "e", function()
    local id = get_selected_id()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if id and opts.on_edit then
      opts.on_edit(id)
    end
  end, { buffer = buf, silent = true })
end

return M
