local M = {}

M.comments = {}
M.next_id = 1
M.session_id = os.date("%Y%m%d-%H%M%S")

function M.add(comment)
  local id = M.next_id
  M.next_id = M.next_id + 1
  comment.id = id
  M.comments[id] = comment
  return comment
end

function M.update(id, updates)
  local comment = M.comments[id]
  if not comment then
    return nil
  end
  for key, value in pairs(updates) do
    comment[key] = value
  end
  return comment
end

function M.delete(id)
  M.comments[id] = nil
end

function M.get(id)
  return M.comments[id]
end

function M.list()
  local items = {}
  for _, comment in pairs(M.comments) do
    table.insert(items, comment)
  end
  table.sort(items, function(a, b)
    return a.id < b.id
  end)
  return items
end

function M.clear()
  M.comments = {}
  M.next_id = 1
end

return M
