local M = {}

local function format_metadata(comment)
  local lines = {}
  table.insert(lines, string.format("- ID: %d", comment.id))
  table.insert(lines, string.format("- File: `%s`", comment.file or "(unknown)"))
  table.insert(lines, string.format("- Lines: %d-%d", comment.range.start_line, comment.range.end_line))
  table.insert(lines, string.format("- Side: %s", comment.side or "current"))
  table.insert(lines, string.format("- Kind: %s", comment.kind or "line"))
  table.insert(lines, string.format("- Timestamp: %s", comment.timestamp or ""))
  return lines
end

local function format_code(comment)
  local lang = comment.filetype or ""
  local lines = { "```" .. lang }
  for _, line in ipairs(comment.code or {}) do
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = "```"
  return lines
end

function M.render_comment(comment)
  local lines = {}
  lines[#lines + 1] = string.format("## Comment %d", comment.id)
  lines[#lines + 1] = ""
  for _, line in ipairs(format_metadata(comment)) do
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "### Comment"
  lines[#lines + 1] = ""
  for _, line in ipairs(vim.split(comment.text or "", "\n", { plain = true })) do
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "### Code"
  lines[#lines + 1] = ""
  for _, line in ipairs(format_code(comment)) do
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = ""
  return lines
end

function M.render_all(comments)
  local lines = {
    "# Code Review",
    "",
  }
  for _, comment in ipairs(comments) do
    for _, line in ipairs(M.render_comment(comment)) do
      lines[#lines + 1] = line
    end
  end
  return lines
end

function M.write_lines(path, lines)
  local ok = pcall(vim.fn.mkdir, vim.fs.dirname(path), "p")
  if not ok then
    return nil, "Failed to create export directory"
  end
  local fd = io.open(path, "w")
  if not fd then
    return nil, "Failed to open export file"
  end
  for _, line in ipairs(lines) do
    fd:write(line)
    fd:write("\n")
  end
  fd:close()
  return path
end

return M
