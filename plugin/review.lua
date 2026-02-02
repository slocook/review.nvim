local review = require("review")

if not review._commands_registered then
  review._commands_registered = true

  vim.api.nvim_create_user_command("ReviewComment", function(opts)
    review.comment(opts)
  end, { range = true })

  vim.api.nvim_create_user_command("ReviewList", function()
    review.list_comments()
  end, {})

  vim.api.nvim_create_user_command("ReviewExport", function()
    review.export()
  end, {})

  vim.api.nvim_create_user_command("ReviewDelete", function()
    review.delete_comment_at_cursor()
  end, {})
end
