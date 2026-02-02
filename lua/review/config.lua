local M = {}

M.defaults = {
  export = {
    mode = "single", -- "single" | "per_comment"
    dir = vim.fn.stdpath("cache") .. "/review.nvim",
  },
  beads = {
    enabled = false,
    cmd = "bd",
    extra_args = {},
    body_mode = "body-file", -- "body-file" | "none"
    parent_from_branch = true,
    branch_pattern = "epic/([^/]+)",
    prompt_if_missing = true,
  },
  ui = {
    border = "rounded",
    width = 0.7,
    height = 0.6,
    preview_height = 0.35,
    title = "Review Comment",
    float_border = "rounded",
    float_anchor = "left", -- "left" | "cursor"
    auto_show_float = false,
    keymaps = {
      submit = "<C-s>",
      cancel = "q",
    },
  },
}

function M.merge(opts)
  return vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

return M
