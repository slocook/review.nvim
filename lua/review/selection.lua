local M = {}

local function normalize_mark(mark)
  return { line = mark[1], col = mark[2] + 1 }
end

local function get_visual_kind()
  local mode = vim.fn.visualmode()
  if mode == "V" then
    return "line"
  end
  if mode == "\22" then
    return "block"
  end
  return "char"
end

local function normalize_codediff_uri(name)
  if not name:match("^codediff://") then
    return name
  end
  local stripped = name:gsub("^codediff://", "")
  local parts = vim.split(stripped, "///", { plain = true, trimempty = true })
  if #parts >= 2 then
    local repo = parts[1]
    local rel = parts[#parts] or ""
    local rel_parts = vim.split(rel, "/", { plain = true, trimempty = true })
    if #rel_parts >= 2 and rel_parts[1]:match("^[0-9a-fA-F]+$") then
      table.remove(rel_parts, 1)
    end
    local relpath = table.concat(rel_parts, "/")
    return repo .. "/" .. relpath
  end
  return name
end

local function get_buffer_path(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name ~= "" then
    return normalize_codediff_uri(name)
  end
  return nil
end

local function resolve_diff_peer(buf)
  local tab = vim.api.nvim_get_current_tabpage()
  local wins = vim.api.nvim_tabpage_list_wins(tab)
  for _, win in ipairs(wins) do
    local win_buf = vim.api.nvim_win_get_buf(win)
    if win_buf ~= buf and vim.wo[win].diff then
      local name = vim.api.nvim_buf_get_name(win_buf)
      if name ~= "" and vim.loop.fs_stat(name) then
        return name
      end
    end
  end
  return nil
end

local function capture_block(buf, start_line, end_line, start_col, end_col)
  local lines = {}
  local start_col0 = start_col - 1
  local end_col0 = end_col
  for line = start_line, end_line do
    local chunk = vim.api.nvim_buf_get_text(buf, line - 1, start_col0, line - 1, end_col0, {})
    lines[#lines + 1] = chunk[1] or ""
  end
  return lines
end

local function capture_lines(buf, start_line, end_line)
  return vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
end

function M.capture_visual(buf)
  local kind = get_visual_kind()
  local start_mark = normalize_mark(vim.api.nvim_buf_get_mark(buf, "<"))
  local end_mark = normalize_mark(vim.api.nvim_buf_get_mark(buf, ">"))

  local start_line = math.min(start_mark.line, end_mark.line)
  local end_line = math.max(start_mark.line, end_mark.line)
  local start_col = math.min(start_mark.col, end_mark.col)
  local end_col = math.max(start_mark.col, end_mark.col)

  local code
  if kind == "block" then
    code = capture_block(buf, start_line, end_line, start_col, end_col)
  else
    code = capture_lines(buf, start_line, end_line)
    kind = "line"
  end

  local file_path = get_buffer_path(buf)
  local peer_path = resolve_diff_peer(buf)

  return {
    bufnr = buf,
    kind = kind,
    file = file_path or peer_path,
    buffer_name = file_path or "",
    side = file_path and "current" or "base",
    filetype = vim.bo[buf].filetype,
    range = {
      start_line = start_line,
      end_line = end_line,
      start_col = start_col,
      end_col = end_col,
    },
    code = code,
  }
end

function M.capture_current_line(buf)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local code = capture_lines(buf, line, line)
  local file_path = get_buffer_path(buf)
  local peer_path = resolve_diff_peer(buf)
  local end_col = 0
  if code[1] then
    end_col = #code[1]
  end

  return {
    bufnr = buf,
    kind = "line",
    file = file_path or peer_path,
    buffer_name = file_path or "",
    side = file_path and "current" or "base",
    filetype = vim.bo[buf].filetype,
    range = {
      start_line = line,
      end_line = line,
      start_col = 1,
      end_col = end_col,
    },
    code = code,
  }
end

return M
