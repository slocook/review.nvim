# review.nvim

Capture review comments directly from diffs, then export to markdown or create Beads subtasks.

## Features

- Line/block capture in diffs (CodeDiff) or normal buffers
- Floating comment editor with selection preview
- Comment list with jump, edit, delete
- Diagnostics signs + popup preview for comments
- Export as single markdown or per-comment markdown
- Optional Beads integration (`bd create`)

## Requirements

- Neovim 0.12+
- Optional: `bd` CLI for Beads integration

## Install (Lazy.nvim)

```lua
{
  "slocook/review.nvim",
  dependencies = {
    "esmuellert/codediff.nvim",
  },
  config = function()
    require("review").setup({
      export = {
        mode = "single", -- "single" | "per_comment"
      },
      beads = {
        enabled = false,
        branch_pattern = "epic/([^/]+)",
      },
    })
  end,
}
```

## Usage

1. Open a diff with CodeDiff (or any buffer).
2. Select lines (visual line or block mode) and run `:ReviewComment`.
3. Use `:ReviewList` to jump/edit/delete comments.
4. Run `:ReviewExport` to export or create beads.

## Commands

- `:ReviewComment` — Capture comment from visual selection or current line
- `:ReviewList` — Open comment list (jump/edit/delete)
- `:ReviewShow` — Show comment at cursor in a floating window
- `:ReviewExport` — If beads enabled, create bead(s); otherwise write markdown
- `:ReviewDelete` — Delete comment covering current line

## Export

- Default path: `stdpath("cache")/review.nvim`
- Mode:
  - `single` — one markdown file for the full review
  - `per_comment` — one markdown file per comment

## Beads integration

If `beads.enabled = true`, `:ReviewExport` will create beads instead of writing markdown.

```lua
require("review").setup({
  beads = {
    enabled = true,
    cmd = "bd",
    parent_from_branch = true,
    branch_pattern = "epic/([^/]+)",
    prompt_if_missing = true,
  },
})
```

If branch inference fails and prompting is enabled, you will be asked for a parent bead id.

## Configuration

```lua
require("review").setup({
  export = {
    mode = "single",
    dir = vim.fn.stdpath("cache") .. "/review.nvim",
  },
  beads = {
    enabled = false,
    cmd = "bd",
    extra_args = {},
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
  },
})
```

## Notes

- Comments live in memory for the current session (persistence is planned).
- For CodeDiff, navigation keeps the 3‑column layout intact.
